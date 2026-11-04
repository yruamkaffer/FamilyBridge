# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'time'
require 'tmpdir'
require 'sketchup.rb'
require_relative 'settings'
require_relative 'aps_connection'
require_relative 'cloud_converter'

module YruamKaffer
  module FamilyBridge
    VERSION = '0.9.4' unless const_defined?(:VERSION)
    DICT = 'YruamKaffer_FamilyBridge' unless const_defined?(:DICT)
    FIELDS = %w[manufacturer code name collection finish description website category].freeze unless const_defined?(:FIELDS)

    class << self
      def safe_filename(value, preserve_spaces: false)
        name = value.to_s.strip.gsub(/[\\\/<>:"|?*\x00-\x1f]/, '_')
        name = name.gsub(/\s+/, '_') unless preserve_spaces
        name = name.sub(/\A\.+/, '').sub(/\.+\z/, '')[0, 80]
        name = 'produto' if name.empty?
        name = '_'+name if name.match?(/\A(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|\z)/i)
        name
      end

      def model_metadata(model)
        FIELDS.each_with_object({}) do |field, hash|
          hash[field] = model.get_attribute(DICT, field, '').to_s
        end
      end

      def info
        model = Sketchup.active_model
        { 'file' => (model.path.to_s.empty? ? 'Modelo não salvo' : File.basename(model.path)),
          'dimensions_mm' => dimensions_mm(model),
          'saved' => model_metadata(model),
          'format' => 'SKP 2020', 'extension_version' => VERSION }
      end

      def dimensions_mm(model)
        bounds = model.bounds
        { 'x' => (bounds.width.to_f * 25.4).round(2),
          'y' => (bounds.height.to_f * 25.4).round(2),
          'z' => (bounds.depth.to_f * 25.4).round(2) }
      end

      def normalize_data(obj)
        raise ArgumentError, 'Dados inválidos' unless obj.is_a?(Hash)
        clean = {}
        FIELDS.each do |field|
          clean[field] = obj.fetch(field, '').to_s.strip[0, 1000]
        end
        clean['category'] = 'Generic Models' if clean['category'].empty?
        unless ['Generic Models', 'Plumbing Fixtures', 'Mechanical Equipment', 'Furniture'].include?(clean['category'])
          raise ArgumentError, 'Categoria não suportada'
        end
        raise ArgumentError, 'Preencha o código do produto' if clean['code'].empty?
        raise ArgumentError, 'Preencha o nome do produto' if clean['name'].empty?
        clean
      end

      def store_metadata(model, data)
        model.start_operation('FamilyBridge - Salvar dados BIM', true)
        begin
          data.each { |k, v| model.set_attribute(DICT, k, v) }
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def export_package(data)
        model = Sketchup.active_model
        data = normalize_data(data)
        step_source = @step_source
        raise 'Selecione o arquivo STEP do produto antes de gerar.' unless step_source && File.file?(step_source)
        raise 'O STEP selecionado está vazio ou é grande demais (máximo 100 MB).' unless (1..100 * 1024 * 1024).cover?(File.size(step_source))
        raise 'Arquivo STEP inválido: cabeçalho ISO-10303-21 ausente.' unless File.open(step_source, 'rb') { |f| f.read(256).to_s.include?('ISO-10303-21') }
        chosen = UI.select_directory(title: 'Escolha a pasta de destino do pacote FamilyBridge')
        return nil if chosen.nil? || chosen.empty?

        slug = safe_filename([data['code'], data['name']].join('_'))
        original = model.path.to_s
        rfa_basename = original.empty? ? slug : safe_filename(File.basename(original, File.extname(original)), preserve_spaces: true)
        folder = File.join(chosen, slug)
        # Criação exclusiva: colisões nunca podem apagar um pacote anterior.
        begin
          Dir.mkdir(folder)
        rescue Errno::EEXIST
          folder = Dir.mktmpdir("#{slug}_", chosen)
        end
        begin
          store_metadata(model, data)
          skp_path = File.join(folder, 'model.skp')
          unless model.save_copy(skp_path, Sketchup::Model::VERSION_2020) && File.file?(skp_path)
            raise 'O SketchUp não conseguiu salvar a cópia em SKP 2020.'
          end
          FileUtils.cp(step_source, File.join(folder, 'model.step'))
          payload = {
            'schema_version' => 1,
            'output_name' => rfa_basename + '.rfa',
            'generator' => { 'name' => 'FamilyBridge', 'version' => VERSION,
                             'author' => 'Yruam Käffer de Faria' },
            'product' => data,
            'geometry' => { 'file' => 'model.step', 'format' => 'STEP ISO 10303',
                            'unit' => 'mm', 'dimensions_mm' => dimensions_mm(model) },
            'exported_at_utc' => Time.now.utc.iso8601
          }
          File.write(File.join(folder, 'metadata.json'), JSON.pretty_generate(payload), mode: 'w:UTF-8')
          File.write(File.join(folder, 'README.txt'), <<~TXT, mode: 'w:UTF-8')
            FamilyBridge v#{VERSION} — pacote para geração de RFA
            Autor: Yruam Käffer de Faria

            model.skp     — cópia do modelo em formato SketchUp 2020
            model.step    — sólido CAD selecionado para a conversão
            metadata.json — informações BIM do produto e dimensões

            Este pacote NÃO é um arquivo RFA. Para gerar uma família .rfa
            é necessário executar o conversor via Revit Automation (APS)
            com Fusion Automation e Revit Automation 2024.
          TXT
          begin
            model.active_view.write_image(filename: File.join(folder, 'preview.png'),
                                          width: 1280, height: 720, antialias: true)
          rescue StandardError
            # A prévia é opcional; nunca cancelar a exportação pela ausência dela.
          end
          folder
        rescue StandardError
          FileUtils.remove_entry(folder) if File.directory?(folder)
          raise
        end
      end

      def show_dialog
        @dialog ||= begin
          dialog = UI::HtmlDialog.new(dialog_title: 'FamilyBridge | STEP → RFA 2024',
                                      preferences_key: 'YruamKaffer.FamilyBridge.v1',
                                      scrollable: true, resizable: true,
                                      width: 590, height: 750,
                                      style: UI::HtmlDialog::STYLE_DIALOG)
          dialog.set_file(File.join(__dir__, 'panel.html'))
          dialog.set_on_closed { @dialog = nil }
          dialog.add_action_callback('get_model') do |_context|
            dialog.execute_script("FamilyBridge.load(#{JSON.generate(info)})")
          end
          dialog.add_action_callback('open_settings') { |_context| show_settings }
          dialog.add_action_callback('select_step') do |_context|
            chosen = UI.openpanel('Escolha o sólido STEP correspondente ao produto', nil, 'Arquivos STEP|*.step;*.stp||')
            if chosen && !chosen.empty?
              if !File.file?(chosen) || !chosen.match?(/\.(?:step|stp)\z/i)
                dialog.execute_script("FamilyBridge.fail(#{JSON.generate('Selecione um arquivo .step ou .stp válido.')})")
              else
                @step_source = chosen
                dialog.execute_script("FamilyBridge.stepSelected(#{JSON.generate(File.basename(chosen))})")
              end
            end
          end
          dialog.add_action_callback('generate_rfa') do |_context, raw|
            begin
              if @cloud_converter && @cloud_converter.running
                raise 'Há uma conversão em andamento. Aguarde o resultado para não enviar outro job.'
              end
              settings_store.credentials
              folder = export_package(JSON.parse(raw))
              if folder
                progress = proc do |message|
                  dialog.execute_script("FamilyBridge.progress(#{JSON.generate(message)})") if @dialog.equal?(dialog)
                end
                completion = proc do |ok, message|
                  if @dialog.equal?(dialog)
                    method = ok ? 'done' : 'fail'
                    dialog.execute_script("FamilyBridge.#{method}(#{JSON.generate(message)})")
                  else
                    UI.messagebox(message)
                  end
                end
                @cloud_converter = CloudConverter.new(folder, settings_store, progress, completion)
                @cloud_converter.start
              else
                dialog.execute_script("FamilyBridge.done('Conversão cancelada antes de qualquer envio.')")
              end
            rescue StandardError => e
              dialog.execute_script("FamilyBridge.fail(#{JSON.generate(e.message)})")
            end
          end
          dialog.add_action_callback('retry_revit') do |_context|
            begin
              raise 'Há uma conversão em andamento.' if @cloud_converter && @cloud_converter.running
              settings_store.credentials
              source = UI.select_directory(title: 'Escolha o pacote original v0.9.2+ com SAT e STEP separados')
              if source.nil? || source.empty?
                dialog.execute_script("FamilyBridge.done(#{JSON.generate('Reprocessamento cancelado.')})")
              else
                fusion = JSON.parse(File.read(File.join(source, 'aps-job.json'), encoding: 'UTF-8'))
                revit = JSON.parse(File.read(File.join(source, 'aps-revit-job.json'), encoding: 'UTF-8'))
                raise 'O job Fusion anterior não foi confirmado.' unless fusion['stage'] == 'fusion' && fusion['state'] == 'success' && fusion['downloaded'] == true
                raise 'O job Revit anterior não está marcado como falho; confira o estado na APS.' unless revit['stage'] == 'revit' && revit['state'].to_s.start_with?('failed')
                %w[bodies.fbdat steps.fbdat colors.json metadata.json].each do |name|
                  raise "Arquivo ausente ou vazio: #{name}" unless File.file?(File.join(source, name)) && File.size(File.join(source, name)) > 0
                end
                folder = Dir.mktmpdir('FamilyBridge_revit_', File.dirname(source))
                %w[bodies.fbdat steps.fbdat colors.json metadata.json].each { |name| FileUtils.cp(File.join(source, name), folder) }
                File.write(File.join(folder, 'README.txt'), "Reprocessamento Revit a partir dos SATs e STEPs separados de #{source}.\nUm novo WorkItem Revit será enviado; o Fusion não será executado.\n", mode: 'w:UTF-8')
                progress = proc { |message| dialog.execute_script("FamilyBridge.progress(#{JSON.generate(message)})") if @dialog.equal?(dialog) }
                completion = proc do |ok, message|
                  if @dialog.equal?(dialog)
                    dialog.execute_script("FamilyBridge.#{ok ? 'done' : 'fail'}(#{JSON.generate(message)})")
                  else
                    UI.messagebox(message)
                  end
                end
                @cloud_converter = CloudConverter.new(folder, settings_store, progress, completion)
                @cloud_converter.start(revit_only: true)
              end
            rescue StandardError => e
              dialog.execute_script("FamilyBridge.fail(#{JSON.generate(e.message)})")
            end
          end
          dialog.add_action_callback('save_data') do |_context, raw|
            begin
              data = normalize_data(JSON.parse(raw))
              store_metadata(Sketchup.active_model, data)
              dialog.execute_script("FamilyBridge.done(#{JSON.generate('Informações salvas no modelo.')})")
            rescue StandardError => e
              dialog.execute_script("FamilyBridge.fail(#{JSON.generate(e.message)})")
            end
          end
          dialog.add_action_callback('export_data') do |_context, raw|
            begin
              folder = export_package(JSON.parse(raw))
              if folder
                dialog.execute_script("FamilyBridge.done(#{JSON.generate("Pacote criado em: #{folder}")})")
              else
                dialog.execute_script("FamilyBridge.done(#{JSON.generate('Exportação cancelada.')})")
              end
            rescue StandardError => e
              dialog.execute_script("FamilyBridge.fail(#{JSON.generate(e.message)})")
            end
          end
          dialog
        end
        @dialog.show
      end

      def settings_store
        @settings_store ||= SettingsStore.new
      end

      def settings_reply(dialog, method, payload)
        dialog.execute_script("APSSettings.#{method}(#{JSON.generate(payload)})") if @settings_dialog.equal?(dialog)
      end

      def show_settings
        @settings_dialog ||= begin
          dialog = UI::HtmlDialog.new(dialog_title: 'FamilyBridge | Configurações APS',
                                      preferences_key: 'YruamKaffer.FamilyBridge.Settings.v1',
                                      scrollable: true, resizable: true, width: 620, height: 780,
                                      style: UI::HtmlDialog::STYLE_DIALOG)
          connection = APSConnection.new
          dialog.set_file(File.join(__dir__, 'settings.html'))
          dialog.set_on_closed do
            connection.cancel
            @settings_dialog = nil
          end
          dialog.add_action_callback('get_settings') do |_context|
            settings_reply(dialog, 'load', settings_store.public_data)
          end
          dialog.add_action_callback('save_settings') do |_context, raw|
            begin
              connection.cancel
              saved = settings_store.save(JSON.parse(raw))
              settings_reply(dialog, 'saved', saved)
            rescue StandardError => e
              settings_reply(dialog, 'fail', e.message)
            end
          end
          dialog.add_action_callback('test_connection') do |_context, raw|
            begin
              connection.cancel
              saved = settings_store.save(JSON.parse(raw))
              settings_reply(dialog, 'prepared', saved)
              client_id, secret = settings_store.credentials
              connection.test(client_id, secret) { |result| settings_reply(dialog, 'result', result) }
            rescue StandardError => e
              settings_reply(dialog, 'fail', e.message)
            end
          end
          dialog.add_action_callback('clear_settings') do |_context|
            begin
              connection.cancel
              settings_reply(dialog, 'cleared', settings_store.clear)
            rescue StandardError => e
              settings_reply(dialog, 'fail', e.message)
            end
          end
          dialog
        end
        @settings_dialog.show
      end

      def install_toolbar
        return if @toolbar
        @toolbar = UI::Toolbar.new('FamilyBridge')
        [[ 'FamilyBridge — Abrir painel BIM', 'product', proc { show_dialog } ],
         [ 'FamilyBridge — Configurações APS', 'settings', proc { show_settings } ]].each do |label, icon, action|
          command = UI::Command.new(label, &action)
          command.tooltip = label
          command.status_bar_text = icon == 'product' ? 'Preparar dados BIM e gerar uma família RFA pela APS.' : 'Configurar e testar a conexão com a Autodesk APS.'
          command.small_icon = File.join(__dir__, 'icons', "#{icon}_24.png")
          command.large_icon = File.join(__dir__, 'icons', "#{icon}_32.png")
          @toolbar.add_item(command)
        end
        @toolbar.get_last_state == -1 ? @toolbar.show : @toolbar.restore
      end

      def install_menu
        return if @menu_installed
        menu = UI.menu('Extensions').add_submenu('FamilyBridge')
        menu.add_item('Abrir FamilyBridge') { show_dialog }
        menu.add_item('Configurações APS') { show_settings }
        menu.add_item('Mostrar barra FamilyBridge') { @toolbar.show }
        menu.add_separator
        menu.add_item('Sobre / versão') do
          UI.messagebox("FamilyBridge v#{VERSION}\nAutor: Yruam Käffer de Faria\n\nPrepara SKP 2020 + metadata.json.\nA geração RFA exige Revit Automation.")
        end
        @menu_installed = true
      end
    end

    install_menu
    install_toolbar
  end
end
