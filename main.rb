require 'bundler/setup'
require 'mini_racer'
require 'zlib'
require 'stringio'
require 'erb'
require 'benchmark/ips'
require 'benchmark'

NODE_MODULES_DIR = File.expand_path('node_modules', __dir__)

class MiniRacer::Context
  attr_writer :timeout
end

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

class Runner
  def initialize(timeout_in_ms:)
    @timeout_in_ms = timeout_in_ms
    @context = MiniRacer::Context.new
    prepare_context

    @translated = {}
    @errors = {}
    @started_at = {}

    warmup
    check_correctness

    @context.timeout = timeout_in_ms
  end

  def kanji_to_katakana(text)
    cleanup
    @context.eval("translateKanjiToKatakanaSync('#{text}')")

    start = now
    @started_at[text] = now
    while (now - start) < (@timeout_in_ms / 1000.0)
      if (response = @translated.delete(text))
        return response
      end

      if (error = @errors.delete(text))
        raise error
      end

      sleep(0.01)
    end

    raise "Timeout error for text #{text}"
  end

  private

  def prepare_context
    @context.attach 'readFileSync', ->(path) { read_file_sync(path) }
    @context.attach 'puts', ->(s) { puts s }
    @context.attach 'joinPath', ->(*args) { File.expand_path(File.join(*args)) }
    @context.attach 'gunzip', ->(compressed) { gunzip(compressed) }
    @context.attach 'onResponse', ->(text, response) { on_response(text, response) }
    @context.attach 'onError', ->(text, error) { on_error(text, error) }

    @context.eval ERB.new(File.read('template.js.erb')).result_with_hash(node_modules_dir: NODE_MODULES_DIR)
  end

  def warmup
    puts "Warming up..."
    kanji_to_katakana('')
  end

  def check_correctness
    text = "岡川1796, 8701131, 大分県大分市, JAPAN"
    translated = kanji_to_katakana(text)
    expected = "オカカワ1796, 8701131, オオイタケンオオイタシ, JAPAN"
    if translated == expected
      puts "Translation server is up and running!"
    else
      raise "Something is wrong:\nExpected #{expected.inspect}\nTranslated: #{translated.inspect}"
    end
  end

  def read_file_sync(path)
    if path.end_with?('.js') || path.end_with?('.json')
      puts "Reading src file #{path}"
      File.binread(path)
    else
      puts "Loading binary #{path}"
      File.binread(path).bytes
    end
  end

  def gunzip(compressed)
    Zlib::GzipReader.new(StringIO.new(compressed.pack('c*'))).read.bytes
  end

  def on_response(text, response)
    # p ['response', response]
    @translated[text] = response
  end

  def on_error(text, error)
    # p ['error', error]
    @errors[text] = response
  end

  def cleanup
    # puts 'cleanup'
  end
end

runner = Runner.new(timeout_in_ms: 500)


Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 2)

  x.report("Kanji") do
    runner.kanji_to_katakana("岡川1796, 8701131, 大分県大分市, JAPAN")
  end

  x.report("non-Kanji") do
    runner.kanji_to_katakana("AA1796, 8701131, ABCDEF, JAPAN")
  end

  x.compare!
end

Benchmark.bmbm do |x|
  x.report("Kanji") do
    runner.kanji_to_katakana("岡川1796, 8701131, 大分県大分市, JAPAN")
  end
  x.report("non-Kanji") do
    runner.kanji_to_katakana("AA1796, 8701131, ABCDEF, JAPAN")
  end
end
