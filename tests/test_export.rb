# Teste da lógica Ruby sem SketchUp. NÃO testa a validade do arquivo SKP nem RFA.
require 'tmpdir'
require 'json'
require 'fileutils'
require 'minitest/autorun'

class FakeBounds
  def width; 3.0; end
  def height; 4.0; end
  def depth; 5.0; end
end
class FakeView
  def write_image(**options)
    File.binwrite(options[:filename], "png placeholder for unit test")
    true
  end
end
class FakeModel
  attr_reader :saved_path
  def initialize; @attributes = {}; end
  def bounds; FakeBounds.new; end
  attr_accessor :path
  def path; @path || ''; end
  def active_view; FakeView.new; end
  def get_attribute(dict, name, default); @attributes.fetch([dict,name], default); end
  def set_attribute(dict, name, value); @attributes[[dict, name]] = value; end
  def start_operation(*); true; end
  def commit_operation; true; end
  def abort_operation; true; end
  def save_copy(path, version)
    raise "Versão errada #{version}" unless version == 2020
    File.binwrite(path, 'mock SketchUp model')
    @saved_path = path
    true
  end
end
module Sketchup
  class Model; VERSION_2020 = 2020; end
  def self.active_model; @model ||= FakeModel.new; end
end
module UI
  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(*); end
  end
  class Toolbar
    def initialize(*); end
    def add_item(*); end
    def get_last_state; -1; end
    def show; end
    def restore; end
  end
  def self.menu(*); FakeMenu.new; end
  def self.select_directory(**); @dest; end
  def self.destination=(v); @dest=v; end
  class FakeMenu
    def add_submenu(*); self; end
    def add_item(*); end
    def add_separator; end
  end
end
$LOADED_FEATURES << 'sketchup.rb'
require_relative '../sketchup/family_bridge/main'

class FamilyBridgeExportTest < Minitest::Test
  def setup
    @step_dir = Dir.mktmpdir
    @step_path = File.join(@step_dir, 'model.step')
    File.write(@step_path, "ISO-10303-21;\nDATA;\nENDSEC;")
    YruamKaffer::FamilyBridge.instance_variable_set(:@step_source, @step_path)
  end

  def teardown
    YruamKaffer::FamilyBridge.instance_variable_set(:@step_source, nil)
    FileUtils.remove_entry(@step_dir)
  end

  def test_export_package_and_metadata
    Dir.mktmpdir do |root|
      UI.destination = root
      data = {'code'=>'ABC 123', 'name'=>'Torneira teste', 'manufacturer'=>'Fabricante genérico',
              'collection'=>'Linha', 'finish'=>'Cromado'}
      folder = YruamKaffer::FamilyBridge.export_package(data)
      assert File.file?(File.join(folder, 'model.skp'))
      assert File.file?(File.join(folder, 'metadata.json'))
      json = JSON.parse(File.read(File.join(folder, 'metadata.json'), encoding: 'UTF-8'))
      assert_equal 'ABC 123', json.dig('product', 'code')
      assert_equal 'Fabricante genérico', json.dig('product', 'manufacturer')
      assert_equal 'ABC_123_Torneira_teste.rfa', json['output_name']
      assert_equal 'STEP ISO 10303', json.dig('geometry', 'format')
      assert File.file?(File.join(folder, 'model.step'))
      assert_equal 76.2, json.dig('geometry', 'dimensions_mm', 'x')
      assert_equal 101.6, json.dig('geometry', 'dimensions_mm', 'y')
      assert_equal 127.0, json.dig('geometry', 'dimensions_mm', 'z')
      assert_equal 'Generic Models', json.dig('product', 'category')
    end
  end

  def test_rfa_name_follows_saved_sketchup_filename
    Dir.mktmpdir do |root|
      UI.destination=root
      Sketchup.active_model.path='C:/Modelos/Tripé para piso.skp'
      folder=YruamKaffer::FamilyBridge.export_package('code'=>'ABC','name'=>'Outro nome')
      assert_equal 'Tripé para piso.rfa',JSON.parse(File.read(File.join(folder,'metadata.json')))['output_name']
    ensure
      Sketchup.active_model.path=''
    end
  end

  def test_refuse_no_product_code
    assert_raises(ArgumentError) do
      YruamKaffer::FamilyBridge.normalize_data('name'=>'Produto sem código')
    end
  end

  def test_safe_filename
    assert_equal 'A_B_C', YruamKaffer::FamilyBridge.safe_filename('A/B:C')
    assert_equal 'produto', YruamKaffer::FamilyBridge.safe_filename('...')
    assert_equal '_CON', YruamKaffer::FamilyBridge.safe_filename('CON')
    assert_equal '_nul.txt', YruamKaffer::FamilyBridge.safe_filename('nul.txt')
  end

  def test_repeated_exports_never_replace_existing_package
    Dir.mktmpdir do |root|
      UI.destination = root
      data = {'code'=>'ABC', 'name'=>'Produto'}
      first = YruamKaffer::FamilyBridge.export_package(data)
      File.write(File.join(first, 'keep.txt'), 'preservar')
      second = YruamKaffer::FamilyBridge.export_package(data)
      third = YruamKaffer::FamilyBridge.export_package(data)
      assert_equal 3, [first, second, third].uniq.length
      assert_equal 'preservar', File.read(File.join(first, 'keep.txt'))
    end
  end

  def test_unknown_category_is_rejected
    assert_raises(ArgumentError) do
      YruamKaffer::FamilyBridge.normalize_data('code'=>'A', 'name'=>'B', 'category'=>'Unknown')
    end
  end
end
