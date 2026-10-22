# frozen_string_literal: true
require 'json'
require 'base64'
require 'uri'
require 'set'

module YruamKaffer
  module FamilyBridge
    # Native asynchronous SketchUp HTTP: no Python, terminal or background server.
    # This class only authenticates and lists engines; it never submits WorkItems.
    class APSConnection
      TOKEN_URL = 'https://developer.api.autodesk.com/authentication/v2/token'
      ENGINES_URL = 'https://developer.api.autodesk.com/da/us-east/v3/engines'

      def initialize
        @generation = 0
        @requests = []
        @timer = nil
      end

      def cancel
        @generation += 1
        stop_timer
        pending = @requests
        @requests = []
        pending.each do |request|
          begin
            request.cancel
          rescue StandardError
            # Dialog may close after an HTTP response finished.
          end
        end
        @token = nil
        @callback = nil
      end

      def test(client_id, secret, &callback)
        cancel
        generation = @generation
        @callback = callback
        @engines = []
        @pages = Set.new
        @timer = UI.start_timer(60, false) do
          handler = @callback
          cancel
          handler.call('ok' => false, 'message' => 'A consulta demorou demais. Confira sua conexão e tente novamente.') if handler
        end
        headers = { 'Authorization' => 'Basic ' + Base64.strict_encode64("#{client_id}:#{secret}"),
                    'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' }
        body = URI.encode_www_form('grant_type' => 'client_credentials', 'scope' => 'code:all')
        request_json(TOKEN_URL, Sketchup::Http::POST, headers, body, generation) do |result|
          @token = result['access_token']
          raise 'Resposta de autenticação inválida.' unless @token.is_a?(String) && !@token.empty?
          engines_page(nil, generation)
        end
      rescue StandardError
        finish('ok' => false, 'message' => 'Não foi possível iniciar a consulta. Confira as credenciais e tente novamente.')
      end

      private

      def stop_timer
        UI.stop_timer(@timer) if @timer
        @timer = nil
      end

      def finish(result)
        stop_timer
        handler = @callback
        @callback = nil
        @token = nil
        handler.call(result) if handler
      end

      def error_message(code)
        case code
        when 400, 401 then 'Autenticação recusada. Confira o Client ID e o Client Secret.'
        when 403 then 'Acesso negado. Confira a Automation API e a associação da aplicação ao seu hub/plano APS.'
        when 429 then 'Limite de consultas atingido. Aguarde um pouco e tente novamente.'
        else "Falha de comunicação com a Autodesk (HTTP #{code}). Tente novamente."
        end
      end

      def request_json(url, method, headers, body, generation, &handler)
        req = Sketchup::Http::Request.new(url, method)
        req.headers = headers
        req.body = body if body
        @requests << req # Keep alive until completion, as required by SketchUp.
        started = req.start do |request, response|
          @requests.delete(request)
          next if generation != @generation || !@callback
          begin
            code = response.status_code.to_i
            if code < 200 || code >= 300
              finish('ok' => false, 'message' => error_message(code))
            else
              parsed = JSON.parse(response.body.to_s)
              raise 'Resposta inválida' unless parsed.is_a?(Hash)
              handler.call(parsed)
            end
          rescue StandardError
            finish('ok' => false, 'message' => 'A Autodesk retornou uma resposta inesperada. Tente novamente.')
          end
        end
        unless started
          @requests.delete(req)
          finish('ok' => false, 'message' => 'Não foi possível iniciar a conexão com a Autodesk.')
        end
      end

      def engines_page(page, generation)
        url = ENGINES_URL
        url += '?' + URI.encode_www_form('page' => page) if page
        request_json(url, Sketchup::Http::GET, { 'Authorization' => 'Bearer ' + @token,
                                               'Accept' => 'application/json' }, nil, generation) do |result|
          entries = result['data']
          raise 'Lista inválida.' unless entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(String) }
          @engines.concat(entries)
          token = result['paginationToken']
          if token && token != ''
            raise 'Paginação inválida.' unless token.is_a?(String) && !@pages.include?(token) && @pages.size < 100
            @pages.add(token)
            engines_page(token, generation)
          else
            revit = @engines.grep(/Revit/).uniq.sort
            found = revit.include?('Autodesk.Revit+2024')
            finish('ok' => true, 'supports_2024' => found, 'engines' => revit,
                   'message' => found ? 'Conexão confirmada. Revit 2024 listado; o cadastro do conversor será validado ao gerar.' :
                     'Conexão confirmada, mas o Revit 2024 não apareceu na lista de engines.')
          end
        end
      end
    end
  end
end
