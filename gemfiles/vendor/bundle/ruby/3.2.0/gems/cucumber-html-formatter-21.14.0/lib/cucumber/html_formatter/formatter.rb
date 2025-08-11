# frozen_string_literal: true

require 'cucumber/messages'
require 'cucumber/html_formatter/template_writer'
require 'cucumber/html_formatter/assets_loader'

module Cucumber
  module HTMLFormatter
    class Formatter
      attr_reader :out

      def initialize(out)
        @out = out
        @pre_message_written = false
        @first_message = true
      end

      def process_messages(messages)
        write_pre_message
        messages.each { |message| write_message(message) }
        write_post_message
      end

      def write_message(message)
        out.puts(',') unless @first_message
        # Replace < with \x3C
        # https://html.spec.whatwg.org/multipage/scripting.html#restrictions-for-contents-of-script-elements
        out.print(message.to_json.gsub('<', "\\x3C"))

        @first_message = false
      end

      def write_pre_message
        return if @pre_message_written

        out.puts(pre_message)
        @pre_message_written = true
      end

      def write_post_message
        out.print(post_message)
      end

      private

      def pre_message
        [
          template_writer.write_between(nil, '{{title}}'),
          'Cucumber',
          template_writer.write_between('{{title}}', '{{icon}}'),
          AssetsLoader.icon,
          template_writer.write_between('{{icon}}', '{{css}}'),
          AssetsLoader.css,
          template_writer.write_between('{{css}}', '{{custom_css}}'),
          template_writer.write_between('{{custom_css}}', '{{messages}}')
        ].join("")
      end

      def post_message
        [
          template_writer.write_between('{{messages}}', '{{script}}'),
          AssetsLoader.script,
          template_writer.write_between('{{script}}', '{{custom_script}}'),
          template_writer.write_between('{{custom_script}}', nil)
        ].join("")
      end

      def template_writer
        @template_writer ||= TemplateWriter.new(AssetsLoader.template)
      end
    end
  end
end
