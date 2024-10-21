require "chem"
require "hclust"
require "option_parser"

dcds_path = ""
ref_pdb = ""
n_clusters = 50
output_basename = ""

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-d PATH", "--dcds_path=PATH", "Input path for Moltiverse dcds.") do |str|
    dcds_path = str
  end
  parser.on("-r FILE", "--reference_pdb=FILE", "Prepared PDB file to use as reference for pdbs atom names.") do |str|
    unless File.exists?(str)
      STDERR.puts "Error: PDB file not found: #{str}"
      exit(1)
    end
    ref_pdb = str
  end
  parser.on("-n N", "--number_of_clusters=N", "Number of clusters to produce") do |str|
    n_clusters = str.to_i32
  end
  parser.on("-o STRING", "--output_basename=STRING", "Output basename for the sdf file.") do |str|
    output_basename = str
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

puts "Reading DCD files..."
structure = Chem::Structure.from_pdb(ref_pdb)
frames = [] of Chem::Structure
Dir["#{dcds_path}/out*.dcd"].each do |path|
  Chem::DCD::Reader.open(path) do |reader|
    reader.each do |pos|
      frame = structure.clone
      frame.pos = pos
      frames << frame
    end
  end
end
puts "Read #{frames.size} structures"

puts "Calculating RMSD..."
pos = frames.map &.pos.center_at_origin.to_a
dism = HClust::DistanceMatrix.new(frames.size) do |i, j|
  _, rmsd = Chem::Spatial.qcp(pos[i], pos[j])
  rmsd
end

puts "Clustering..."
dendrogram = HClust.linkage(dism, :single)
clusters = dendrogram.flatten(count: n_clusters)
centroids = clusters.map do |idxs|
  frames[idxs[dism[idxs].centroid]]
end
centroids.to_sdf "#{output_basename}"
