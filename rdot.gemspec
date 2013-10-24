# encoding: utf-8

require 'is/build'
require './lib/rdot-common'

Gem::Specification.new do |g|
  g.name = 'rdot'
  g.version = RDot::VERSION
  g.summary = 'GraphViz diagrams for Ruby classes'
  g.author = 'Ivan Shikhalev'
  g.email = 'shikhalev@gmail.com'
  g.description = g.summary + '.'
  g.homepage = 'https://github.com/shikhalev/rdot'
  g.license = 'GNU GPL'

  g.files = Dir['lib/*.rb'] + Dir['*.md'] +
      [ 'bin/rdot', 'bin/rbdot', '.yardopts' ]
  g.executables = ['rdot', 'rbdot']

  g.mkbuild

  g.require_path = 'lib'
  g.required_ruby_version = '>= 1.9.2'
  g.add_dependency 'is-monkey', '~> 0.4'
end
