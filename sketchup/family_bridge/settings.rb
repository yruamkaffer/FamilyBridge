# frozen_string_literal: true
require 'json'
require 'base64'

module YruamKaffer
  module FamilyBridge
    # Windows DPAPI, scoped to the current Windows user. Never uses machine scope.
    # Loaded only when requested; other platforms can use session-only credentials.
    module WindowsSecret
      def self.available?
        Sketchup.platform == :platform_win
      end

      def self.api
        return @api if @api
        raise 'Proteção persistente disponível apenas no Windows 64 bits.' unless available?
        require 'fiddle/import'
        raise 'Proteção persistente exige Windows 64 bits.' unless Fiddle::SIZEOF_VOIDP == 8
        @api = Module.new do
          extend Fiddle::Importer
          dlload 'crypt32.dll', 'kernel32.dll'
          extern 'int CryptProtectData(void*, void*, void*, void*, void*, unsigned int, void*)'
          extern 'int CryptUnprotectData(void*, void*, void*, void*, void*, unsigned int, void*)'
          extern 'void* LocalFree(void*)'
          const_set(:Blob, struct(['unsigned int cbData', 'void* pbData']))
        end
      rescue LoadError
        raise 'A biblioteca de proteção do Windows não está disponível. Use o segredo somente nesta sessão.'
      end

      def self.transform(bytes, protect)
        native = api
        input = Fiddle::Pointer.malloc(bytes.bytesize, Fiddle::RUBY_FREE)
        input[0, bytes.bytesize] = bytes
        source = native::Blob.malloc(Fiddle::RUBY_FREE)
        target = native::Blob.malloc(Fiddle::RUBY_FREE)
        source.cbData = bytes.bytesize
        source.pbData = input
        target.cbData = 0
        target.pbData = 0
        method = protect ? :CryptProtectData : :CryptUnprotectData
        # CRYPTPROTECT_UI_FORBIDDEN = 1; optional description and entropy omitted.
        ok = native.public_send(method, source, nil, nil, nil, nil, 1, target)
        raise 'Não foi possível usar a proteção de credenciais do Windows.' if ok == 0
        output = Fiddle::Pointer.new(target.pbData.to_i)
        output[0, target.cbData]
      ensure
        input[0, bytes.bytesize] = "\0" * bytes.bytesize if input
        if output && !output.null?
          output[0, target.cbData] = "\0" * target.cbData
          native.LocalFree(output)
        end
      end

      def self.protect(text)
        Base64.strict_encode64(transform(text.encode(Encoding::UTF_8), true))
      end

      def self.unprotect(encoded)
        transform(Base64.strict_decode64(encoded), false).force_encoding(Encoding::UTF_8)
      end
    end

    class SettingsStore
      PREFS = 'YruamKaffer.FamilyBridge.APS'
      ENVELOPE = 'FBAPS1:'

      def initialize(protector = WindowsSecret)
        @protector = protector
        @secret = nil
        @secret_client_id = nil
      end

      def persisted
        raw = Sketchup.read_default(PREFS, 'settings', '{}')
        # Some SketchUp preference implementations interpret a JSON-looking value
        # as Ruby data, returning a Hash (including Symbol keys) instead of text.
        # Read legacy forms, but always write an ASCII envelope from this version.
        if raw.is_a?(String) && raw.start_with?(ENVELOPE)
          raw = Base64.strict_decode64(raw.delete_prefix(ENVELOPE)).force_encoding(Encoding::UTF_8)
        end
        obj = raw
        2.times { obj = JSON.parse(obj) if obj.is_a?(String) }
        obj.is_a?(Hash) ? obj.each_with_object({}) { |(key, value), hash| hash[key.to_s] = value } : {}
      rescue JSON::ParserError, TypeError, ArgumentError
        {}
      end

      def persist_verified(settings)
        encoded = ENVELOPE + Base64.strict_encode64(JSON.generate(settings).encode(Encoding::UTF_8))
        saved = Sketchup.write_default(PREFS, 'settings', encoded)
        raise 'Não foi possível salvar as configurações. Os campos foram mantidos para tentar novamente.' unless saved
        unless persisted == settings
          raise 'O SketchUp não recuperou as configurações gravadas. Os campos foram mantidos; tente salvar novamente.'
        end
      end

      def public_data
        settings = persisted
        { 'client_id' => settings.fetch('client_id', ''),
          'owner' => settings.fetch('owner', ''), 'alias' => settings.fetch('alias', 'dev'),
          'has_secret' => !settings['client_id'].to_s.empty? &&
            ((!@secret.to_s.empty? && @secret_client_id == settings['client_id']) || !settings['protected_secret'].to_s.empty?),
          'remember' => !settings['protected_secret'].to_s.empty?,
          'can_remember' => @protector.available? }
      end

      def save(data)
        raise ArgumentError, 'Configuração inválida.' unless data.is_a?(Hash)
        current = persisted
        cid = data['client_id'].to_s.strip
        owner = data['owner'].to_s.strip
        label = data.fetch('alias', 'dev').to_s.strip
        raise ArgumentError, 'Preencha o Client ID.' unless cid.match?(/\A[A-Za-z0-9_-]{1,256}\z/)
        raise ArgumentError, 'Owner inválido.' unless owner.empty? || owner.match?(/\A[A-Za-z0-9_-]{1,256}\z/)
        raise ArgumentError, 'Alias inválido.' unless label.match?(/\A[A-Za-z0-9_-]{1,64}\z/)
        entered = data['secret'].to_s.strip
        raise ArgumentError, 'Client Secret inválido.' if entered.bytesize > 4096 || entered.match?(/[\r\n\x00]/)
        same_client = current['client_id'] == cid
        value = entered.empty? && same_client ? secret : entered
        remember = data['remember'] == true
        updated = { 'client_id' => cid, 'owner' => owner, 'alias' => label }
        if remember
          raise ArgumentError, 'Proteção persistente indisponível. Desmarque Lembrar segredo.' unless @protector.available?
          raise ArgumentError, 'Preencha o Client Secret para lembrar.' if value.to_s.empty?
          updated['protected_secret'] = @protector.protect(value)
          unless @protector.unprotect(updated['protected_secret']) == value
            raise 'A proteção do Windows não recuperou o segredo corretamente. Os campos foram mantidos.'
          end
        end
        persist_verified(updated)
        @secret = value
        @secret_client_id = cid
        public_data
      end

      def secret
        settings = persisted
        return @secret if !@secret.to_s.empty? && @secret_client_id == settings['client_id']
        sealed = settings['protected_secret'].to_s
        return '' if sealed.empty?
        @secret = @protector.unprotect(sealed)
        @secret_client_id = settings['client_id']
        @secret
      rescue StandardError
        raise 'Não foi possível recuperar o segredo salvo. Digite o Client Secret novamente.'
      end

      def credentials
        config = persisted
        value = secret
        raise ArgumentError, 'Preencha Client ID e Client Secret antes de testar.' if config['client_id'].to_s.empty? || value.to_s.empty?
        [config['client_id'], value]
      end

      def clear
        persist_verified({})
        @secret = nil
        @secret_client_id = nil
        public_data
      end
    end
  end
end
