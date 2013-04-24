# encoding: utf-8

require './lib/rdot'

Gem::Specification.new do |g|
  g.name = 'rdot'
  g.version = RDot::VERSION
  g.summary = 'GraphViz class diagrams for Ruby'
  g.author = 'Ivan Shikhalev'
  g.email = 'shikhalev@gmail.com'
  g.description = g.summary + '.'
  g.homepage = 'https://github.com/shikhalev/rdot/'
  g.license = 'GNU GPL'

  g.files = Dir['lib/*.rb'] + Dir['*.md'] + [ 'bin/rdot', '.yardopts' ]
  g.executables = ['rdot']
  g.require_path = 'lib'
  g.required_ruby_version = '>= 1.9.2'
end
