# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module YruamKaffer
  module FamilyBridge
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('FamilyBridge', 'family_bridge/main')
      extension.description = 'Prepara modelos SketchUp e dados BIM para geração de famílias RFA com Revit Automation.'
      extension.version = '0.9.5'
      extension.creator = 'Yruam Käffer de Faria'
      extension.copyright = '© 2026 Yruam Käffer de Faria'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
