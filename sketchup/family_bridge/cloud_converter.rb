# frozen_string_literal: true
require 'json'
require 'base64'
require 'uri'
require 'securerandom'
require 'digest'

module YruamKaffer
  module FamilyBridge
    # All CAD execution happens in APS. No local Revit, Python or web server.
    # No purchase, subscription change, or automatic retry of a WorkItem POST.
    class CloudConverter
      DA = 'https://developer.api.autodesk.com/da/us-east/v3'
      OSS = 'https://developer.api.autodesk.com/oss/v2'
      AUTH = 'https://developer.api.autodesk.com/authentication/v2/token'
      ENGINE = 'Autodesk.Revit+2024'
      FUSION_ENGINE = 'Autodesk.Fusion+Latest'
      FUSION_BUNDLE = 'FamilyBridgeStepToSat'
      FUSION_ACTIVITY = 'FamilyBridgeStepToSatActivity'
      # Autodesk SDK sample, unchanged. Revit 2024 must upgrade this older template.
      TEMPLATE = 'https://raw.githubusercontent.com/jeremytammik/RevitSdkSamples/4ca6a3d6f0ae6e166b514e8324f65f057da27b64/snapshot/2022/Samples/FreeFormElement/Generic%20Model.rft'
      BUNDLE = 'FamilyBridgeAutomation2024'
      ACTIVITY = 'FamilyBridgeRfa2024'
      attr_reader :running

      def initialize(folder, settings, progress, completion)
        @folder, @settings, @progress, @completion = folder, settings, progress, completion
        @running = false
        @timer = nil
      end

      def start(revit_only: false)
        raise 'Já há uma conversão em andamento.' if @running
        @revit_only = revit_only
        @client_id, @secret = @settings.credentials
        @redactions = [@client_id, @secret, Base64.strict_encode64("#{@client_id}:#{@secret}")]
        config = @settings.public_data
        @owner = config['owner'].to_s.empty? ? @client_id : config['owner']
        @alias = config['alias']
        [@owner, @alias].each { |s| raise 'Owner/alias inválido.' unless s.to_s.match?(/\A[A-Za-z0-9_-]+\z/) }
        @bundle_file = File.join(__dir__, 'resources', 'FamilyBridgeAutomation2024.bundle.zip')
        raise 'Pacote do conversor ausente. Reinstale o FamilyBridge.' unless File.file?(@bundle_file)
        (revit_only ? %w[bodies.fbdat steps.fbdat colors.json metadata.json] : %w[model.step metadata.json]).each do |name|
          path = File.join(@folder, name)
          raise "Arquivo ausente ou vazio: #{name}" unless File.file?(path) && File.size(path) > 0
          raise 'Este protótipo aceita entradas de até 100 MB por arquivo.' if File.size(path) > 100 * 1024 * 1024
        end
        metadata = parse(File.read(File.join(@folder, 'metadata.json'), encoding: 'UTF-8'))
        if revit_only
          colors = parse(File.read(File.join(@folder, 'colors.json'), encoding: 'UTF-8'))
          raise 'Este pacote tem isolamento antigo; execute uma conversão completa para preservar a orientação das peças.' unless colors['isolation_coordinates'] == 'assembly_mm'
          raise 'Manifesto de cores inválido.' unless colors['schema_version'] == 1 && colors['bodies'].is_a?(Array) && !colors['bodies'].empty?
          validate_body_archive(File.binread(File.join(@folder, 'bodies.fbdat')), colors['bodies'].length)
          validate_step_archive(File.binread(File.join(@folder, 'steps.fbdat')), colors['bodies'].length)
        end
        @output_name = metadata.fetch('output_name', 'output.rfa').to_s
        basename = @output_name.sub(/\.rfa\z/i, '')
        if @output_name.length > 120 || basename.empty? ||
           !@output_name.match?(/\A[^\\\/<>:"|?*\x00-\x1f]+\.rfa\z/i) ||
           basename.end_with?('.', ' ') ||
           basename.match?(/\A(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])\z/i)
          raise 'Nome de saída RFA inválido no pacote.'
        end
        @running = true
        @job = { 'state' => 'preparing', 'engine' => ENGINE }
        @receipt = File.join(@folder, revit_only ? 'aps-revit-job.json' : 'aps-job.json')
        raise 'Há um recibo de conversão nesta pasta. Confira o job anterior antes de reenviar.' if File.exist?(@receipt)
        @progress.call('Conectando à APS…')
        headers = {'Authorization' => 'Basic ' + Base64.strict_encode64("#{@client_id}:#{@secret}"),
                   'Content-Type' => 'application/x-www-form-urlencoded'}
        body = URI.encode_www_form('grant_type' => 'client_credentials',
                                   'scope' => 'code:all bucket:create bucket:read data:read data:write')
        request(AUTH, 'POST', headers, body) do |code, bytes|
          check(code)
          @token = parse(bytes).fetch('access_token')
          @redactions << @token
          @secret = nil
          # Exact engine check uses the endpoint, not only the first list page.
          api(DA, 'GET', '/engines/Autodesk.Revit%2B2024') do |_r|
            if @revit_only
              resolve_owner
            else
              api(DA, 'GET', '/engines/Autodesk.Fusion%2BLatest') { |_f| resolve_owner }
            end
          end
        end
      rescue StandardError => e
        finish(false, e.message)
      end

      private

      def finish(ok, message)
        UI.stop_timer(@timer) if @timer
        @timer = nil
        @running = false
        unless ok
          begin
            File.write(File.join(@folder, 'aps-diagnostic.json'), JSON.pretty_generate({
              'version' => '0.9.4', 'request' => @http_context, 'http_status' => @http_status,
              'message' => sanitize(message), 'job_id' => @job && @job['id'],
              'remote_state' => @job && @job['state']
            }), mode: 'w:UTF-8')
          rescue StandardError
            # Diagnostics must never hide the original failure.
          end
        end
        @token = @secret = nil
        @redactions = nil
        callback = @completion
        @completion = nil
        callback.call(ok, message) if callback
      end

      def check(code, accepted = [200, 201, 202, 204])
        return if accepted.include?(code)
        message = case code
                  when 400 then 'A APS recusou os dados desta requisição.'
                  when 401 then 'A autenticação desta chamada foi recusada pela APS.'
                  when 403 then 'Acesso negado ou franquia indisponível. Confira Automation API, Data Management/OSS e o consumo do plano Free no portal Autodesk. Nenhum plano pago foi ativado.'
                  when 404 then 'Recurso APS não encontrado. Confira o engine, owner e acesso da aplicação.'
                  when 429 then 'Limite de requisições da APS atingido. Aguarde antes de tentar novamente.'
                  else "Falha na comunicação com a APS (HTTP #{code})."
                  end
        stage = @stage == :fusion ? 'Fusion' : 'Revit 2024'
        message = "#{@http_context} (#{stage}) — HTTP #{code}. #{message}"
        message += " Motivo: #{@response_details}" unless @response_details.to_s.empty?
        if @job && @job['state'] == 'submitting'
          message += ' O envio pode ter sido aceito; não reenvie sem conferir a APS e aps-job.json.'
        end
        raise message
      end

      def sanitize(value)
        result = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        Array(@redactions).reject { |v| v.to_s.empty? }.sort_by { |v| -v.length }.each do |secret|
          result = result.gsub(secret, '[oculto]')
        end
        result.gsub(%r{https?://[^\s<>"']+}, '[URL ocultada]')
              .gsub(/(?:Bearer|Basic)\s+[^\s,;]+/i, '[autorização ocultada]')
              .gsub(/[A-Za-z0-9_+\/=.-]{48,}/, '[identificador ocultado]')[0, 1200]
      end

      def sanitize_report(report)
        # Signed URLs may contain spaces, escaped quotes and query strings.
        # Remove the whole URL field/line tail before the usual secret filter.
        report.gsub(/\r\n?/, "\n").lines.map do |line|
          clean = if line.match?(/"url"\s*:/i)
                    line.sub(/("url"\s*:).*/i, '\\1 "[URL ocultada]",')
                  else
                    line.sub(%r{https?://.*}i, '[URL ocultada]')
                  end
          sanitize(clean.chomp) + "\n"
        end.join
      end

      def response_details(bytes)
        data = JSON.parse(bytes.to_s)
        return sanitize(data) if data.is_a?(String)
        values = []
        collect_error_messages(data, values)
        sanitize(values.reject(&:empty?).uniq.join(' | '))[0, 900]
      rescue JSON::ParserError
        raw = bytes.to_s.strip
        raw.start_with?('<') ? '' : sanitize(raw)[0, 900]
      end

      def collect_error_messages(node, values, depth = 0)
        return if depth > 4 || values.length >= 12
        case node
        when String
          values << node[0, 400]
        when Array
          node.first(12).each { |item| collect_error_messages(item, values, depth + 1) }
        when Hash
          node.each do |key, value|
            next if key.to_s.match?(/token|secret|credential|password|signature|policy|authorization|url|client.?id/i)
            next unless value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(String)
            collect_error_messages(value, values, depth + 1)
          end
        end
      end

      def resolve_owner
        @progress.call('Conferindo o identificador da aplicação na APS…')
        api(DA, 'GET', '/forgeapps/me') do |nickname|
          raise 'A APS retornou um identificador de aplicação inválido.' unless nickname.is_a?(String) && nickname.match?(/\A[A-Za-z0-9_-]+\z/)
          @owner = nickname
          @stage = @revit_only ? :revit : :fusion
          @engine = @revit_only ? ENGINE : FUSION_ENGINE
          @bundle = @revit_only ? BUNDLE : FUSION_BUNDLE
          @activity = @revit_only ? ACTIVITY : FUSION_ACTIVITY
          @bundle_file = File.join(__dir__, 'resources', @revit_only ? 'FamilyBridgeAutomation2024.bundle.zip' : 'FamilyBridgeStepToSat.bundle.zip')
          publish_bundle
        end
      end

      def parse(bytes)
        JSON.parse(bytes.to_s)
      rescue JSON::ParserError
        raise 'Resposta inesperada da APS. Nenhum token ou conteúdo da resposta foi registrado.'
      end

      def request(url, method, headers = {}, body = nil, &handler)
        raise 'Somente conexões HTTPS são aceitas.' unless URI.parse(url).scheme == 'https'
        req = Sketchup::Http::Request.new(url, method)
        req.headers = headers
        req.body = body if body
        @request = req
        @timer = UI.start_timer(120, false) do
          @request.cancel if @request
          finish(false, 'Tempo de rede esgotado. Se o envio do job já começou, confira aps-job.json e a APS antes de reenviar.')
        end
        started = req.start do |_request, response|
          next unless @running
          UI.stop_timer(@timer) if @timer
          @timer = nil
          @request = nil
          begin
            uri = URI.parse(url)
            endpoint = if uri.host == 'developer.api.autodesk.com'
                         uri.path.sub(%r{/objects/.*}, '/objects/[arquivo]').sub(%r{/workitems/.*}, '/workitems/[job]')
                       else
                         '[transferência de arquivo]'
                       end
            @http_context = method + ' ' + endpoint
            @http_status = response.status_code.to_i
            @response_details = response_details(response.body) unless (200...300).include?(@http_status)
            @response_details = '' if (200...300).include?(@http_status)
            handler.call(@http_status, response.body)
          rescue StandardError => e
            finish(false, e.is_a?(KeyError) || e.is_a?(TypeError) ? 'Resposta APS incompleta ou inválida.' : e.message)
          end
        end
        raise 'Não foi possível iniciar a requisição de rede.' unless started
      end

      def api(base, method, path, body = nil, accepted = [200, 201, 202, 204], &handler)
        headers = {'Authorization' => 'Bearer ' + @token, 'Accept' => 'application/json'}
        headers['Content-Type'] = 'application/json' if body
        request(base + path, method, headers, body && JSON.generate(body)) do |code, bytes|
          check(code, accepted)
          handler.call(bytes.to_s.empty? ? {} : parse(bytes), code)
        end
      end

      def publish_bundle
        @progress.call('Preparando o conversor na sua conta APS…')
        body = {'id' => @bundle, 'engine' => @engine}
        api(DA, 'POST', '/appbundles', body, [200, 201, 409]) do |result, code|
          if code == 409
            api(DA, 'POST', "/appbundles/#{@bundle}/versions", {'engine' => @engine}) { |r| upload_bundle(r) }
          else
            upload_bundle(result)
          end
        end
      end

      def upload_bundle(result)
        params = result.fetch('uploadParameters')
        boundary = 'FamilyBridge' + SecureRandom.hex(12)
        content = +''.b
        params.fetch('formData').each do |key, value|
          raise 'Campo de upload inválido.' if key.match?(/[\r\n"]/)
          content << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n".b
        end
        content << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"bundle.zip\"\r\nContent-Type: application/zip\r\n\r\n".b
        content << File.binread(@bundle_file) << "\r\n--#{boundary}--\r\n".b
        request(params.fetch('endpointURL'), 'POST', {'Content-Type' => "multipart/form-data; boundary=#{boundary}"}, content) do |code, _|
          check(code)
          set_alias('appbundles', @bundle, result.fetch('version')) { publish_activity }
        end
      end

      def set_alias(resource, name, version, &next_step)
        path = "/#{resource}/#{name}/aliases"
        api(DA, 'POST', path, {'id' => @alias, 'version' => version}, [200, 201, 409]) do |_r, code|
          if code == 409
            api(DA, 'PATCH', path + '/' + @alias, {'version' => version}) { |_v| next_step.call }
          else
            next_step.call
          end
        end
      end

      def publish_activity
        qualified_bundle = "#{@owner}.#{@bundle}+#{@alias}"
        if @stage == :fusion
          parameters = {'InputFile' => {'verb' => 'get', 'required' => true, 'localName' => 'inputFile.step'},
                        'OutputFile' => {'verb' => 'put', 'required' => true, 'localName' => 'outputFile.sat'},
                        'ColorFile' => {'verb' => 'put', 'required' => true, 'localName' => 'colors.json'},
                        'BodyFiles' => {'verb' => 'put', 'required' => true, 'localName' => 'bodies.fbdat'},
                        'StepFiles' => {'verb' => 'put', 'required' => true, 'localName' => 'steps.fbdat'}}
          command_line = []
        else
          parameters = {'geometry' => 'bodies.fbdat', 'steps' => 'steps.fbdat', 'metadata' => 'metadata.json', 'colors' => 'colors.json',
                        'familyTemplate' => 'template.rft', 'result' => 'output.rfa'}
                       .transform_values { |name| {'verb' => name == 'output.rfa' ? 'put' : 'get', 'required' => true, 'localName' => name} }
          command_line = ['"$(engine.path)\\revitcoreconsole.exe" /al "$(appbundles[' + @bundle + '].path)"']
        end
        spec = {'id' => @activity, 'engine' => @engine, 'appbundles' => [qualified_bundle],
                'commandLine' => command_line, 'parameters' => parameters}
        api(DA, 'POST', '/activities', spec, [200, 201, 409]) do |result, code|
          if code == 409
            spec.delete('id')
            api(DA, 'POST', "/activities/#{@activity}/versions", spec) { |r| activate_activity(r) }
          else
            activate_activity(result)
          end
        end
      end

      def activate_activity(result)
        set_alias('activities', @activity, result.fetch('version')) do
          if @stage == :fusion
            @stage = :revit
            @engine = ENGINE
            @bundle = BUNDLE
            @activity = ACTIVITY
            @bundle_file = File.join(__dir__, 'resources', 'FamilyBridgeAutomation2024.bundle.zip')
            publish_bundle
          else
            @bucket = 'familybridge-' + Digest::SHA256.hexdigest(@client_id)[0, 32]
            @prefix = SecureRandom.hex(12)
            api(OSS, 'POST', '/buckets', {'bucketKey' => @bucket, 'policyKey' => 'transient'}, [200, 201, 409]) do |_r|
              @inputs = {}
              if @revit_only
                upload_input('geometry', 'bodies.fbdat') do
                  upload_input('steps', 'steps.fbdat') do
                    upload_input('metadata', 'metadata.json') do
                      upload_input('colors', 'colors.json') { prepare_revit_result }
                    end
                  end
                end
              else
                upload_input('InputFile', 'model.step') { upload_input('metadata', 'metadata.json') { prepare_fusion_result } }
              end
            end
          end
        end
      end

      def object_path(name)
        "/buckets/#{@bucket}/objects/" + URI.encode_www_form_component(@prefix + '-' + name)
      end

      def upload_input(key, name, &next_step)
        @progress.call("Enviando #{name} para o armazenamento temporário da APS…")
        path = object_path(name)
        api(OSS, 'GET', path + '/signeds3upload?parts=1&minutesExpiration=60') do |signed|
          request(signed.fetch('urls').fetch(0), 'PUT', {}, File.binread(File.join(@folder, name))) do |code, _|
            check(code)
            api(OSS, 'POST', path + '/signeds3upload', {'uploadKey' => signed.fetch('uploadKey')}) do |_r|
              api(OSS, 'GET', path + '/signeds3download?minutesExpiration=60') do |download|
                @inputs[key] = {'url' => download.fetch('url'), 'verb' => 'get'}
                next_step.call
              end
            end
          end
        end
      end

      def prepare_fusion_result
        @result_path = object_path('output.sat')
        api(OSS, 'GET', @result_path + '/signeds3upload?parts=1&minutesExpiration=60') do |signed|
          @output_key = signed.fetch('uploadKey')
          @color_result_path = object_path('colors.json')
          api(OSS, 'GET', @color_result_path + '/signeds3upload?parts=1&minutesExpiration=60') do |color_signed|
            @color_output_key = color_signed.fetch('uploadKey')
            @body_result_path = object_path('bodies.fbdat')
            api(OSS, 'GET', @body_result_path + '/signeds3upload?parts=1&minutesExpiration=60') do |body_signed|
              @body_output_key = body_signed.fetch('uploadKey')
              @step_result_path = object_path('steps.fbdat')
              api(OSS, 'GET', @step_result_path + '/signeds3upload?parts=1&minutesExpiration=60') do |step_signed|
                @step_output_key = step_signed.fetch('uploadKey')
                args = {'InputFile' => @inputs.fetch('InputFile'),
                        'OutputFile' => {'url' => signed.fetch('urls').fetch(0), 'verb' => 'put'},
                        'ColorFile' => {'url' => color_signed.fetch('urls').fetch(0), 'verb' => 'put'},
                        'BodyFiles' => {'url' => body_signed.fetch('urls').fetch(0), 'verb' => 'put'},
                        'StepFiles' => {'url' => step_signed.fetch('urls').fetch(0), 'verb' => 'put'}}
                @job = {'state' => 'submitting', 'engine' => FUSION_ENGINE,
                        'activity' => "#{@owner}.#{FUSION_ACTIVITY}+#{@alias}", 'stage' => 'fusion'}
                File.write(@receipt, JSON.pretty_generate(@job), mode: 'wx:UTF-8')
                @progress.call('Convertendo STEP e separando os corpos sólidos…')
                submit_workitem(args)
              end
            end
          end
        end
      end

      def prepare_revit_result
        @result_path = object_path('output.rfa')
        api(OSS, 'GET', @result_path + '/signeds3upload?parts=1&minutesExpiration=60') do |signed|
          @output_key = signed.fetch('uploadKey')
          args = {'geometry' => @inputs.fetch('geometry'), 'steps' => @inputs.fetch('steps'),
                  'metadata' => @inputs.fetch('metadata'), 'colors' => @inputs.fetch('colors'),
                  'familyTemplate' => {'url' => TEMPLATE, 'verb' => 'get'},
                  'result' => {'url' => signed.fetch('urls').fetch(0), 'verb' => 'put'}}
          @job = {'state' => 'submitting', 'engine' => ENGINE,
                  'activity' => "#{@owner}.#{ACTIVITY}+#{@alias}", 'stage' => 'revit'}
          # Keep both receipts; the first job ID remains available for diagnosis.
          @receipt = File.join(@folder, 'aps-revit-job.json')
          File.write(@receipt, JSON.pretty_generate(@job), mode: 'wx:UTF-8')
          @progress.call('Criando família no Revit 2024 da APS…')
          submit_workitem(args)
        end
      end

      def submit_workitem(args)
        api(DA, 'POST', '/workitems', {'activityId' => @job['activity'], 'arguments' => args,
                                    'limitProcessingTimeSec' => 600}) do |result|
          @job['id'] = result.fetch('id')
          @job['state'] = result.fetch('status', 'pending')
          write_receipt
          @polls = 0
          poll
        end
      end

      def write_receipt
        # No tokens, secrets, upload keys or signed URLs in this receipt.
        File.write(@receipt, JSON.pretty_generate(@job), mode: 'w:UTF-8')
      end

      def poll
        @polls += 1
        raise "Acompanhamento encerrado após 15 minutos. Job #{@job['id']} pode continuar na APS; não reenvie." if @polls > 180
        api(DA, 'GET', '/workitems/' + URI.encode_www_form_component(@job['id'])) do |result|
          status = result.fetch('status')
          @job['state'] = status
          write_receipt
          @progress.call("Job #{@job['id']}: #{status}…")
          if status == 'success'
            @job['stage'] == 'fusion' ? finalize_fusion_output : finalize_output
          elsif status.start_with?('failed') || status == 'cancelled'
            message = "A APS encerrou o job com #{status}. ID: #{@job['id']}. Guarde aps-job.json para diagnóstico; ainda não houve RFA confirmado."
            if result['reportUrl']
              request(result['reportUrl'], 'GET') do |code, bytes|
                if (200...300).include?(code)
                  report = bytes.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
                  report = sanitize_report(report)
                  report_name = @job['stage'] == 'fusion' ? 'aps-fusion-report.txt' : 'aps-revit-report.txt'
                  File.write(File.join(@folder, report_name), report, mode: 'w:UTF-8')
                  message += " Relatório salvo em #{report_name}."
                end
                finish(false, message)
              end
            else
              finish(false, message)
            end
          else
            @timer = UI.start_timer(5, false) { @timer = nil; poll }
          end
        end
      rescue StandardError => e
        finish(false, e.message)
      end

      def finalize_fusion_output
        api(OSS, 'POST', @result_path + '/signeds3upload', {'uploadKey' => @output_key}) do |_r|
          api(OSS, 'GET', @result_path + '/signeds3download?minutesExpiration=60') do |download|
            @progress.call('Conferindo o SAT produzido…')
            request(download.fetch('url'), 'GET') do |code, bytes|
              check(code)
              raw = bytes.to_s.b
              # ASCII ACIS starts with a numeric version. Revit 2024 accepts up to 7.0.
              version = raw.byteslice(0, 40).to_s[/\A\s*(\d+)\s+/, 1].to_i
              raise "SAT incompatível com Revit 2024 (versão #{version})." unless (1..700).cover?(version)
              raise 'SAT vazio ou sem entidades ACIS.' if raw.bytesize < 100 || !raw.include?('body')
              File.open(File.join(@folder, 'model.sat'), 'wbx') { |file| file.write(raw) }
              @job['downloaded'] = true
              write_receipt
              finalize_fusion_colors
            end
          end
        end
      end

      def finalize_fusion_colors
        api(OSS, 'POST', @color_result_path + '/signeds3upload', {'uploadKey' => @color_output_key}) do |_r|
          api(OSS, 'GET', @color_result_path + '/signeds3download?minutesExpiration=60') do |download|
            request(download.fetch('url'), 'GET') do |code, bytes|
              check(code)
              colors = parse(bytes)
              bodies = colors.fetch('bodies')
              raise 'Fusion não confirmou as coordenadas das peças.' unless colors['isolation_coordinates'] == 'assembly_mm'
              raise 'Fusion não retornou cores por sólido.' unless colors['schema_version'] == 1 && bodies.is_a?(Array) && !bodies.empty?
              File.write(File.join(@folder, 'colors.json'), JSON.pretty_generate(colors), mode: 'wx:UTF-8')
              finalize_fusion_bodies(bodies.length)
            end
          end
        end
      end

      def validate_body_archive(raw, expected_count)
        raise 'Arquivo dos SATs separados inválido ou maior que 100 MB.' unless raw.start_with?('FBB1') && raw.bytesize.between?(12, 100 * 1024 * 1024)
        count = raw.byteslice(4, 4).unpack1('V')
        raise 'Quantidade de SATs individuais difere das cores.' unless count == expected_count && (1..256).cover?(count)
        offset = 8
        count.times do |index|
          raise 'Arquivo dos SATs individuais truncado.' if offset + 4 > raw.bytesize
          size = raw.byteslice(offset, 4).unpack1('V')
          offset += 4
          raise "SAT individual #{index + 1} inválido." unless (100..100 * 1024 * 1024).cover?(size) && offset + size <= raw.bytesize
          header = raw.byteslice(offset, 40).to_s
          version = header[/\A\s*(\d+)\s+/, 1].to_i
          raise "SAT individual #{index + 1} incompatível com Revit 2024." unless (1..700).cover?(version)
          offset += size
        end
        raise 'Arquivo dos SATs individuais contém dados extras.' unless offset == raw.bytesize
      end

      def validate_step_archive(raw, expected_count)
        raise 'Arquivo dos STEPs separados inválido ou maior que 100 MB.' unless raw.start_with?('FBS1') && raw.bytesize.between?(32, 100 * 1024 * 1024)
        count = raw.byteslice(4, 4).unpack1('V')
        raise 'Quantidade de STEPs individuais difere das cores.' unless count == expected_count && (1..256).cover?(count)
        offset = 8
        count.times do |index|
          raise 'Arquivo dos STEPs individuais truncado.' if offset + 4 > raw.bytesize
          size = raw.byteslice(offset, 4).unpack1('V')
          offset += 4
          raise "STEP individual #{index + 1} inválido." unless (20..100 * 1024 * 1024).cover?(size) && offset + size <= raw.bytesize
          raise "STEP individual #{index + 1} sem cabeçalho ISO." unless raw.byteslice(offset, 12) == 'ISO-10303-21'
          offset += size
        end
        raise 'Arquivo dos STEPs individuais contém dados extras.' unless offset == raw.bytesize
      end

      def finalize_fusion_bodies(expected_count)
        api(OSS, 'POST', @body_result_path + '/signeds3upload', {'uploadKey' => @body_output_key}) do |_r|
          api(OSS, 'GET', @body_result_path + '/signeds3download?minutesExpiration=60') do |download|
            request(download.fetch('url'), 'GET') do |code, bytes|
              check(code)
              raw = bytes.to_s.b
              validate_body_archive(raw, expected_count)
              File.open(File.join(@folder, 'bodies.fbdat'), 'wbx') { |file| file.write(raw) }
              finalize_fusion_steps(expected_count)
            end
          end
        end
      end

      def finalize_fusion_steps(expected_count)
        api(OSS, 'POST', @step_result_path + '/signeds3upload', {'uploadKey' => @step_output_key}) do |_r|
          api(OSS, 'GET', @step_result_path + '/signeds3download?minutesExpiration=60') do |download|
            request(download.fetch('url'), 'GET') do |code, bytes|
              check(code)
              raw = bytes.to_s.b
              validate_step_archive(raw, expected_count)
              File.open(File.join(@folder, 'steps.fbdat'), 'wbx') { |file| file.write(raw) }
              upload_input('geometry', 'bodies.fbdat') do
                upload_input('steps', 'steps.fbdat') do
                  upload_input('colors', 'colors.json') { prepare_revit_result }
                end
              end
            end
          end
        end
      end

      def finalize_output
        api(OSS, 'POST', @result_path + '/signeds3upload', {'uploadKey' => @output_key}) do |_r|
          api(OSS, 'GET', @result_path + '/signeds3download?minutesExpiration=60') do |download|
            @progress.call('Baixando o RFA gerado…')
            request(download.fetch('url'), 'GET') do |code, bytes|
              check(code)
              raw = bytes.to_s.b
              raise 'A saída não tem assinatura de contêiner Revit. Nenhum RFA foi salvo.' unless raw.start_with?([0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1].pack('C*'))
              output = File.join(@folder, @output_name)
              File.open(output, 'wbx') { |file| file.write(raw) }
              @job['downloaded'] = true
              write_receipt
              finish(true, "RFA recebido da APS: #{output}\nA geração precisa ser conferida em um visualizador compatível ou pelo destinatário no Revit.")
            end
          end
        end
      end
    end
  end
end
