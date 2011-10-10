#!/usr/bin/ruby -Ku

require 'pp'

$rd_out = $stdout
$rd_log = $stderr

def out lo, hi = lo
  if $rd_out.stat.chardev?
    $rd_out.puts hi
  else
    $rd_out.puts lo
  end
end

def log lo, hi = lo
  if $rd_log.stat.chardev?
    $rd_log.puts hi
  else
    $rd_log.puts lo
  end
end

$rd_dot = {
  :title => 'RDot: %s',
  :font => {
    :node => 'Monospace',
    :graph => 'Sans-Serif'
  },
  :color => {
    :class => {
      :normal => 'mediumaquamarine',
      :preloaded => 'mediumseagreen',
      :evaluated => 'aquamarine'
    },
    :module => {
      :normal => 'skyblue',
      :preloaded => 'steelblue'
    },
    :exception => {
      :normal => 'lightcoral',
      :preloaded => 'chocolate',
      :evaluated => 'lightpink'
    },
    :edge => {
      :inherited => 'steelblue',
      :included => 'skyblue',
      :extended => 'olivedrab'
    },
    :method => {
      :protected => '#EEEEEE',
      :private => '#DDDDDD'
    }
  }
}

$rd_exclude = []
$rd_include = []

$rd_except = []

$rd_show_protected = false
$rd_show_private = false
$rd_show_preloaded = false

$rd_hide_methods = false
$rd_hide_constants = false
$rd_hide_arguments = false

$rd_trace = true

$rd_verbosity = :none


