require "chem"
require "hclust"
require "option_parser"
include Chem

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

structure = Chem::Structure.from_pdb(ref_pdb)
frames : Array(Chem::Structure) = [] of Chem::Structure
span_rmsd : Array(Float64) = [] of Float64
groups : Array(Array(Chem::Structure)) = [] of Array(Chem::Structure)

puts "Reading dcd files..."
Dir["#{dcds_path}/out*.dcd"].each do |dcd|
  Chem::DCD::Reader.open((dcd), structure) do |reader|
    n_frames = reader.n_entries - 1
    (0..n_frames).each do |frame|
      st = reader.read_entry frame
      frames.push(st)
    end
  end
end

def grouping(frames : Array(Chem::Structure), groups : Array(Array(Chem::Structure)))
  count = 0
  grupito : Array(Chem::Structure) = [] of Chem::Structure
  frames.each_with_index do |st, index|
    grupito.push(st)
    if grupito.size >= 3
      dism = HClust::DistanceMatrix.new(grupito.size) { |a, b|
        grupito[a].coords.rmsd grupito[b].coords, minimize: true
      }
      span = dism.to_a.max - dism.to_a.min
      if span > 1.5 || grupito.size >= 200
        count += 1
        puts "Group #{count} with #{grupito.size} structures and span of #{span} Å created"
        groups.push(grupito)
        grupito = [] of Chem::Structure
      end
    end
  end
  groups.push(grupito)
  groups
end

def subclustering(structures : Array(Chem::Structure), n_clusters : Int32)
  clustering_result : Array(Chem::Structure) = [] of Chem::Structure

  dism = HClust::DistanceMatrix.new(structures.size) { |a, b|
    structures[a].coords.rmsd structures[b].coords, minimize: true
  }
  dendrogram = HClust.linkage(dism, :single)
  clusters = dendrogram.flatten(count: n_clusters)
  # Get centroid indexes
  centroids = clusters.map do |idxs|
    idxs[dism[idxs].centroid]
  end
  clustering_result = clusters.map do |idxs|
    structures[idxs[dism[idxs].centroid]]
  end
  clustering_result
end

puts "Grouping structures..."
grupos = grouping(frames, groups)

puts "Performing the first clustering by groups..."
first_clustering : Array(Chem::Structure) = [] of Chem::Structure
grupos.each do |grupito|
  if grupito.size >= 3
    dism = HClust::DistanceMatrix.new(grupito.size) { |a, b|
      grupito[a].coords.rmsd grupito[b].coords, minimize: true
    }
    span = dism.to_a.max - dism.to_a.min
    if span <= 1.5 && grupito.size >= 5
      clustering_result = subclustering(grupito, 5)
      clustering_result.each do |st|
        first_clustering.push(st)
      end
    elsif span > 1.5 && span <= 2.5 && grupito.size >= 10
      clustering_result = subclustering(grupito, 10)
      clustering_result.each do |st|
        first_clustering.push(st)
      end
    elsif span > 2.5 && span <= 3.75 && grupito.size >= 15
      clustering_result = subclustering(grupito, 15)
      clustering_result.each do |st|
        first_clustering.push(st)
      end
    elsif span > 3.75 && span <= 5.0 && grupito.size >= 20
      clustering_result = subclustering(grupito, 20)
      clustering_result.each do |st|
        first_clustering.push(st)
      end
    elsif span > 5.0 && span <= 7.5 && grupito.size >= 30
      clustering_result = subclustering(grupito, 30)
      clustering_result.each do |st|
        first_clustering.push(st)
      end
    else
      grupito.each do |st|
        first_clustering.push(st)
      end
    end
  else
    grupito.each do |st|
      first_clustering.push(st)
    end
  end
end

puts "Performing the second clustering by groups..."
puts "Analizyng #{first_clustering.size} structures"
second_clustering = subclustering(first_clustering, 250)
second_clustering.to_sdf "#{output_basename}"
puts "Done!"
exit(1)
