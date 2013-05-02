# encoding: utf-8

require 'rdot-common'

module Kernel

  alias :rbdot_original_require :require

  def require lib
    result = rbdot_original_require lib
  end

  private :rbdot_original_require, :require

end

module RbDot

  EXTENSIONS = ['.rb', '.so', '.o', '.dll']

  class << self

    def find_file name
      case File.extname(name).downcase
      when *EXTENSIONS
        return name
      else
        EXTENSIONS.each do |ext|
          fn = name + ext
          $:.each do |path|
            if File.exists?(File.join(path, fn))
              return fn
            end
          end
        end
      end
      nil
    end

    def register_link from_file, from_line, to
      @links ||= []
      link = {
        :from => {
                  :file => RDot.get_file(from_file),
                  :line => from_line
                 },
        :to => find_file(to)
      }
      @links << link
    end

  end

end
