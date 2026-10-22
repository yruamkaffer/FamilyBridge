require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'uri'
module Sketchup
  module Http
    Reply = Struct.new(:status_code, :body)
    class Request
      attr_accessor :headers, :body
      attr_reader :url, :method
      class << self; attr_accessor :pending, :all; end
      def initialize(url, method); @url, @method = url, method; self.class.all << self; end
      def start(&block); @callback = block; self.class.pending << self; true; end
      def cancel; end
      def reply(code, value); @callback.call(self, Reply.new(code, value.is_a?(String) ? value : JSON.generate(value))); end
    end
  end
end
module UI
  class << self
    attr_accessor :timers
    def start_timer(*, &block); @timers ||= {}; id = @timers.length + 1; @timers[id] = block; id; end
    def stop_timer(id); @timers.delete(id); end
  end
end
require_relative '../sketchup/family_bridge/cloud_converter'

class SolidPipelineTest < Minitest::Test
  Request = Sketchup::Http::Request
  MAGIC = [0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1].pack('C*')
  Settings = Struct.new(:nothing) do
    def credentials; %w[Client123 TEST_SECRET]; end
    def public_data; {'alias' => 'dev'}; end
  end
  def setup
    @folder = Dir.mktmpdir
    File.write(File.join(@folder, 'model.step'), 'ISO-10303-21;DATA;ENDSEC;')
    File.write(File.join(@folder, 'metadata.json'), JSON.generate({'output_name' => 'bucha_fix_piso.rfa'}))
    Request.all = []; Request.pending = []; UI.timers = {}
    @results = []; @jobs = 0
    @sat = '700 0 1 0\nbody $-1 solid\n' + 'x' * 100
    @converter = YruamKaffer::FamilyBridge::CloudConverter.new(@folder, Settings.new, proc { |_| }, proc { |ok, msg| @results << [ok, msg] })
  end
  def teardown; FileUtils.remove_entry(@folder); end
  def response(req)
    path = URI(req.url).path
    return [200, {'access_token' => 'TEST_TOKEN'}] if path.end_with?('/authentication/v2/token')
    return [200, JSON.generate('Client123')] if path.end_with?('/forgeapps/me')
    return [200, {}] if path.include?('/engines/')
    if path.end_with?('/appbundles') || path.end_with?('/appbundles/versions')
      return [201, {'version' => 1, 'uploadParameters' => {'endpointURL' => 'https://uploads.example/bundle', 'formData' => {'key' => 'bundle'}}}]
    end
    return [201, {'version' => 1}] if path.end_with?('/activities')
    return [201, {}] if path.end_with?('/aliases')
    return [204, ''] if URI(req.url).host == 'uploads.example'
    return [201, {}] if path.end_with?('/buckets')
    if path.end_with?('/signeds3upload')
      return req.method == 'GET' ? [200, {'uploadKey' => 'UPLOAD_KEY', 'urls' => ['https://uploads.example/file']}] : [200, {}]
    end
    if path.end_with?('/signeds3download')
      return [200, {'url' => path.include?('output.sat') ? 'https://downloads.example/sat' :
                            path.include?('colors.json') ? 'https://downloads.example/colors' :
                            path.include?('output.rfa') ? 'https://downloads.example/rfa' : 'https://downloads.example/input'}]
    end
    if path.end_with?('/workitems')
      @jobs += 1
      return [200, {'id' => "job-#{@jobs}", 'status' => 'pending'}]
    end
    return [200, {'status' => 'success'}] if path.include?('/workitems/')
    return [200, @sat] if req.url == 'https://downloads.example/sat'
    return [200, {'schema_version' => 1, 'bodies' => [{'dimensions_mm' => [10, 10, 10],
              'volume_mm3' => 1000, 'rgb' => [230, 180, 100]}]}] if req.url == 'https://downloads.example/colors'
    return [200, MAGIC + 'RFA'] if req.url == 'https://downloads.example/rfa'
    raise "Unhandled #{req.method} #{path}"
  end
  def flow
    @converter.start
    count = 0
    until Request.pending.empty?
      raise 'Request loop' if (count += 1) > 80
      req = Request.pending.shift
      req.reply(*response(req))
    end
  end
  def job_payloads
    Request.all.select { |r| r.url.end_with?('/workitems') && r.method == 'POST' }.map { |r| JSON.parse(r.body) }
  end
  def test_full_two_stage_flow
    flow
    assert @results.first.first, @results.inspect
    assert_equal 2, @jobs
    assert_equal 'Client123.FamilyBridgeStepToSatActivity+dev', job_payloads[0]['activityId']
    assert_equal 'Client123.FamilyBridgeRfa2024+dev', job_payloads[1]['activityId']
    assert_equal %w[ColorFile InputFile OutputFile], job_payloads[0]['arguments'].keys.sort
    assert_equal %w[colors familyTemplate geometry metadata result], job_payloads[1]['arguments'].keys.sort
    assert_equal @sat, File.binread(File.join(@folder, 'model.sat'))
    assert_equal [230, 180, 100], JSON.parse(File.read(File.join(@folder, 'colors.json')))['bodies'][0]['rgb']
    assert File.binread(File.join(@folder, 'bucha_fix_piso.rfa')).start_with?(MAGIC)
    %w[aps-job.json aps-revit-job.json].each do |receipt|
      content = File.read(File.join(@folder, receipt))
      assert JSON.parse(content)['downloaded']
      %w[TEST_SECRET TEST_TOKEN UPLOAD_KEY https://].each { |v| refute_includes content, v }
    end
  end
  def test_newer_sat_does_not_submit_revit_job
    @sat = '800 0 1 0\nbody $-1 solid\n' + 'x' * 100
    flow
    refute @results.first.first
    assert_includes @results.first.last, 'SAT incompatível'
    assert_equal 1, @jobs
    refute File.exist?(File.join(@folder, 'model.sat'))
  end
  def test_existing_receipt_prevents_duplicate_billable_job
    File.write(File.join(@folder, 'aps-job.json'), '{"id":"existing"}')
    flow
    assert_equal 0, @jobs
    assert_empty Request.all
  end
end
