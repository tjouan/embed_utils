# frozen_string_literal: true

module EmbedUtils
  class Board
    class << self
      def [] key
        case key
          when :uno then Board::Uno
          when :micro then Board::Micro
          else fail ArgumentError, "unknown board: `#{key}'"
        end.new
      end
    end

  private

    class Base
      def variant
        :standard
      end

      def predefines
        %w[
          -DARDUINO=167
          -DARDUINO_ARCH_AVR
          -D__PROG_TYPES_COMPAT__
        ]
      end
    end

    class Uno < Base
      def mcu
        :atmega328p
      end

      def predefines
        super + %w[
          -DF_CPU=16000000L
        ]
      end
    end

    class Micro < Base
      def mcu
        :atmega32u4
      end

      def variant
        :micro
      end

      def predefines
        super + %w[
          -DF_CPU=16000000L
          -DUSB_VID=0x2341
          -DUSB_PID=0x8037
        ]
      end
    end
  end
end
