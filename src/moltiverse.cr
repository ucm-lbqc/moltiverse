# TODO: Write documentation for `Moltiverse`
module Moltiverse
  VERSION = "0.1.0"

  # TODO: Put your code here
end


require "chem"
require "option_parser"
require "./prepare.cr"
require "./protocols.cr"
require "colorize"
require "./colors.cr"
require "./dependencies.cr"

include Chem
include Prepare
include Chem::Spatial
include Coloring
include Dependencies


# Define defaults values for parser variables.
ligand = ""
ph_target = 7.0
keep_hydrogens = true
seed_value = "no"
explicit_water = false
output_name = "empty"
bounds_colvars = BoundsColvars.new(0.0, 10.0, 20, 2, 0, 0, 0, 0)
dimension = 1
metadynamics = false

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-l FILE", "--ligand=FILE", "Input ligand file [PDB, MOL or MOL2]") do |str|
    unless File.exists?(str)
      STDERR.puts "Error: ligand file not found: #{str}"
      exit(1)
    end
    ligand = str
  end
