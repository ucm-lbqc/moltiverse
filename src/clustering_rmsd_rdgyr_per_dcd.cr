require "chem"
require "hclust"
require "option_parser"

# #module Chem::Spatial
# #  struct CoordinatesProxy
# #    def rdgyr : Float64
# #      center = self.com
# #      pos = to_a # FIXME: avoid copying coordinates
# #      square_sum = pos.sum do |i|
# #        d = center.distance(i)
# #        d.abs2
# #      end
# #      Math.sqrt(square_sum/pos.size)
# #    end
# #  end
# #end

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

# #Dir["#{dcds_path}/out*.dcd"].each do |dcd|
# #  dcd_frames : Array(Chem::Structure) = [] of Chem::Structure
# #  Chem::DCD::Reader.open((dcd), structure) do |reader|
# #    n_frames = reader.n_entries - 1
# #    (0..n_frames).each do |frame|
# #      st = reader.read_entry frame
# #      dcd_frames.push(st)
# #    end
# #    puts "Analyzing dcd with #{dcd_frames.size} frames"
# #    dism = HClust::DistanceMatrix.new(dcd_frames.size) { |a, b|
# #      dcd_frames[a].coords.rmsd dcd_frames[b].coords, minimize: true
# #    }
# #    # puts "Minimum RMSD: #{dism.to_a.min}"
# #    # puts "Maximum RMSD: #{dism.to_a.max}"
# #    span = dism.to_a.max - dism.to_a.min
# #    span_rmsd.push(span)
# #  end
# #end
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

# def grouping(frames : Array(Chem::Structure), groups : Array(Array(Chem::Structure)))
#  count = 0
#  grupito : Array(Chem::Structure) = [] of Chem::Structure
#  frames.each_with_index do |st, index|
#    grupito.push(st)
#    if grupito.size >= 3
#      dism = HClust::DistanceMatrix.new(grupito.size) { |a, b|
#        grupito[a].coords.rmsd grupito[b].coords, minimize: true
#      }
#      span = dism.to_a.max - dism.to_a.min
#      if span > 1.5 || grupito.size >= 200
#        count += 1
#        puts "Group #{count} with #{grupito.size} structures and span of #{span} Å created"
#        groups.push(grupito)
#        grupito = [] of Chem::Structure
#      end
#    end
#  end
#  groups.push(grupito)
#  groups
# end

def weighted_clustering(frames : Array(Chem::Structure), n_clusters : Int64)
  groups : Array(Array(Chem::Structure)) = [] of Array(Chem::Structure)
  clustering_result : Array(Chem::Structure) = [] of Chem::Structure
  hash = {
    "0.0 - 1.0"  => [] of Chem::Structure,
    "1.0 - 2.0"  => [] of Chem::Structure,
    "2.0 - 3.0"  => [] of Chem::Structure,
    "3.0 - 4.0"  => [] of Chem::Structure,
    "4.0 - 5.0"  => [] of Chem::Structure,
    "5.0 - 6.0"  => [] of Chem::Structure,
    "6.0 - 7.0"  => [] of Chem::Structure,
    "7.0 - 8.0"  => [] of Chem::Structure,
    "8.0 - 9.0"  => [] of Chem::Structure,
    "9.0 - 10.0" => [] of Chem::Structure,
    "other"      => [] of Chem::Structure,
  }
  frames.each_with_index do |st, index|
    rdgyr_value = st.coords.rdgyr
    case rdgyr_value
    when 0..1
      hash["0.0 - 1.0"] << st
    when 1..2
      hash["1.0 - 2.0"] << st
    when 2..3
      hash["2.0 - 3.0"] << st
    when 3..4
      hash["3.0 - 4.0"] << st
    when 4..5
      hash["4.0 - 5.0"] << st
    when 5..6
      hash["5.0 - 6.0"] << st
    when 6..7
      hash["6.0 - 7.0"] << st
    when 7..8
      hash["7.0 - 8.0"] << st
    when 8..9
      hash["8.0 - 9.0"] << st
    when 9..10
      hash["9.0 - 10.0"] << st
    else
      hash["other"] << st
    end
  end

  span_array : Array(Float64) = [] of Float64

  hash.each do |key, structures|
    if structures.size >= 3
      dism = HClust::DistanceMatrix.new(structures.size) { |a, b|
        structures[a].coords.rmsd structures[b].coords, minimize: true
      }
      span = dism.to_a.max - dism.to_a.min
      puts "RDGYR range: #{key}, Size: #{structures.size}, span #{span}"
      span_array.push(span)
      groups.push(structures)
    else
      puts "RDGYR range: #{key}, Size: #{structures.size}, span --"
    end
  end

  total_sum = span_array.sum
  remaining_elements = n_clusters
  elements_per_clusters : Array(Int32) = [] of Int32
  bigger_span = 0
  bigger_idx = 0
  span_array.each_with_index do |span, index|
    if span > bigger_span
      bigger_idx = index
      bigger_span = span
    end
    percentage = ((span / total_sum) * 100)
    element = percentage * n_clusters / 100
    elements = element.round.to_i32
    # TO:DO FIX THIS MONKEY PATCH.
    # Adjust the last percentage to ensure the sum is exactly 100
    # if index == array.size - 1
    #  elements += remaining_elements
    # end
    elements_per_clusters.push(elements)
    remaining_elements -= elements
  end
  puts "Remaining elements to adjust: #{remaining_elements}"
  puts "Bigger RMSD span is #{bigger_span}, element #{bigger_idx} in array"
  if remaining_elements != 0
    elements_per_clusters[bigger_idx] += remaining_elements
  end
  puts "Remaining elements: #{remaining_elements}"
  puts "Number of clusters to generate: #{elements_per_clusters.sum}"
  groups.each_with_index do |grupito, idx|
    clustering_subresult = subclustering(grupito, elements_per_clusters[idx])
    clustering_subresult.each do |st|
      clustering_result.push(st)
    end
  end
  clustering_result
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

puts "Performing weighted clustering..."
clustering_result = weighted_clustering(frames, 250)
clustering_result.to_sdf "#{output_basename}"
puts "Done!"
