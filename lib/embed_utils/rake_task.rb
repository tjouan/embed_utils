# frozen_string_literal: true

require 'rake/tasklib'

require 'embed_utils/board'

module EmbedUtils
  class RakeTask < Rake::TaskLib
    BUILD_DIR     = 'build'
    HEX_FILE      = "#{BUILD_DIR}/main.hex"
    ELF_FILE      = "#{BUILD_DIR}/main.elf"
    LIBS_ARCHIVE  = "#{BUILD_DIR}/libcore.a"

    LIBRARIES     = %w[arduino]
    LIBRARIES_DIR = 'libraries'

    SRC_DIR       = 'src'
    ARDUINO_DIR   = '/usr/local/arduino'

    CC            = 'avr-gcc'
    CXX           = 'avr-g++'
    AR            = 'avr-ar'
    OBJCOPY       = 'avr-objcopy'
    SIZE          = 'avr-size'
    CXXFLAGS      = %w[
      -std=c++11
      -fno-exceptions
    ]

    # FIXME: for default one, sort /dev/cuaU? by date and pick last one
    PORT          = ENV.fetch 'PORT', '/dev/cuaU1'

    attr_reader   :board
    attr_accessor :libs_archive, :libraries, :src_dir, :arduino_dir

    def initialize
      @board        = Board[:uno]
      @libs_archive = LIBS_ARCHIVE
      @libraries    = LIBRARIES
      @src_dir      = SRC_DIR
      @arduino_dir  = ARDUINO_DIR
      yield self if block_given?
      define
    end

    def board= identifier
      @board = Board[identifier]
    end

  private

    def define
      file HEX_FILE => ELF_FILE do |t|
        sh "#{SIZE} #{ELF_FILE}"
        sh "#{OBJCOPY} -O ihex -R .eeprom #{ELF_FILE} #{t.name}"
      end

      file ELF_FILE => [objs, libs_archive] do |t|
        sh "#{CC} #{linker_flags} -o #{t.name} #{t.prerequisites.join ' '}"
      end

      file libs_archive => libs_objs do |t|
        sh "#{AR} rcs #{t.name} #{t.sources.join ' '}"
      end

      libs.each do |lib|
        directory lib_build_dir lib
      end

      rule '.o' => [obj_to_src, *libs_build_dirs] do |t|
        args = [*cpp_flags, *board.predefines, *includes]
        if t.source.pathmap('%x') == '.c'
          sh "#{CC} #{args.join ' '} #{t.source} -c -o #{t.name}"
        else
          args += CXXFLAGS
          sh "#{CXX} #{args.join ' '} #{t.source} -c -o #{t.name}"
        end
      end

      desc 'Build the hex file'
      task hex: HEX_FILE

      desc 'Install program on USB board'
      task install: :hex do
        sh "avrdude -V -p atmega328p -D -c arduino -P #{PORT} -U flash:w:#{HEX_FILE}:i"
      end

      desc 'Remove build directory'
      task :clean do
        rm_rf BUILD_DIR
      end
    end

    def objs
      FileList["#{src_dir}/*.cpp"].pathmap "%{^#{src_dir},#{BUILD_DIR}}X.o"
    end

    def obj_to_src
      -> t do
        if lib = libs.find { |l| lib_objs(l).include? t }
          lib_srcs(lib).find do |e|
            e.pathmap("%{^#{lib_src_dir lib},#{BUILD_DIR}/#{lib}}X") == t.pathmap('%X')
          end
        else
          t.pathmap "%{^#{BUILD_DIR},#{src_dir}}X.cpp"
        end
      end
    end

    def includes
      %W[
        -Iinclude
        -I#{arduino_dir}/hardware/arduino/avr/cores/arduino
        -I#{arduino_dir}/hardware/arduino/avr/variants/#{board.variant}
      ] + libs.select { |lib| lib != 'arduino' }.map do |lib|
        "-I#{lib_include_dir lib}"
      end
    end

    def linker_flags
      "-mmcu=#{board.mcu} -Wl,--gc-sections -Os"
    end

    def cpp_flags
      %W[
        -MMD -mmcu=#{board.mcu}
        -Wall -ffunction-sections -fdata-sections -Os
      ]
    end

    def libs
      libraries
    end

    def libs_objs
      libs.inject [] do |m, lib|
        m + lib_objs(lib)
      end
    end

    def libs_build_dirs
      libs.map do |lib|
        lib_build_dir lib
      end
    end

    def lib_build_dir lib
      "#{BUILD_DIR}/#{lib}"
    end

    def lib_objs lib
      lib_srcs(lib).pathmap "%{^#{lib_src_dir lib},#{BUILD_DIR}/#{lib}}X.o"
    end

    def lib_srcs lib
      [
        FileList["#{lib_src_dir lib}/*.c"],
        FileList["#{lib_src_dir lib}/*.cpp"],
        FileList["#{lib_src_dir lib}/*.S"]
      ].inject :+
    end

    def lib_include_dir lib
      %W[
        #{LIBRARIES_DIR}/#{lib}
        #{arduino_dir}/libraries/#{lib}/src
        #{arduino_dir}/hardware/arduino/avr/libraries/#{lib}
      ].find do |lib_dir|
        Dir.exist? lib_dir
      end
    end

    def lib_src_dir lib
      case lib
      when 'arduino'
        "#{arduino_dir}/hardware/arduino/avr/cores/arduino"
      else
        %W[
          #{LIBRARIES_DIR}/#{lib}
          #{arduino_dir}/libraries/#{lib}/src/avr
          #{arduino_dir}/hardware/arduino/avr/libraries/#{lib}
        ].find do |lib_dir|
          Dir.exist? lib_dir
        end
      end
    end
  end
end
