require "chem"
require "hclust"
require "option_parser"

# module Chem::Spatial
#  struct CoordinatesProxy
#    def rdgyr : Float64
#      center = self.com
#      pos = to_a # FIXME: avoid copying coordinates
#      square_sum = pos.sum do |i|
#        d = center.distance(i)
#        d.abs2
#      end
#      Math.sqrt(square_sum/pos.size)
#    end
#  end
# end

path = ""
output_name = "rmsd_matrix"
# n_clusters = 50

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal moltiverse.cr [OPTIONS]"
  parser.on("-p PATH", "--path=PATH", "Input path for PDB structures") do |str|
    path = str
  end
  # parser.on("-n N", "--number_of_clusters=N", "Number of clusters to produce") do |str|
  #  n_clusters = str.to_i32
  # end
  parser.on("-o NAME", "--output_name=NAME", "Basename for the output file [.dat]. Default: rmsd_matrix") do |str|
    output_name = str
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

def run_cmd(cmd, args)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(cmd, args: args, output: stdout, error: stderr)
  if status.success?
    stdout.to_s
  else
    stderr.to_s
    # exit(1)
  end
end

def write_getidx(outfile : String)
  File.write outfile, <<-SCRIPT
    from rdkit import Chem
    from rdkit.Chem import rdFMCS
    import argparse
    import sys
  
    def parse_args(argv):
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("-a", "--a", help="Structure a")
        parser.add_argument(
            "-b",
            "--b",
            help="Structure b",
        )
        opts = parser.parse_args(argv)
        return opts
  
    def order_list_of_pairs_by_first_element(list_of_pairs):
      sorted_list_of_pairs = sorted(list_of_pairs, key=lambda pair: pair[0])
      # Return the new list of pairs that is ordered by the first element.
      return sorted_list_of_pairs
  
    def main(argv):
      opts = parse_args(argv)
      pose1 = Chem.rdmolfiles.MolFromPDBFile(f"{opts.a}", sanitize=True, removeHs=True)
      pose2 = Chem.rdmolfiles.MolFromPDBFile(f"{opts.b}", sanitize=True, removeHs=True)
  
      try:
          r = rdFMCS.FindMCS([pose1, pose2], timeout=5)
          a = pose1.GetSubstructMatch(Chem.MolFromSmarts(r.smartsString))
          b = pose2.GetSubstructMatch(Chem.MolFromSmarts(r.smartsString))
          amap = list(zip(a, b))
          order = order_list_of_pairs_by_first_element(amap)
          for pair in order:
              print(pose2.GetAtomWithIdx(pair[1]).GetPDBResidueInfo().GetName().strip())
      except RuntimeError as err:
          print(f"Error: {err}")
    if __name__ == "__main__":
        main(sys.argv[1:])
  
    SCRIPT
end

# 1. Order atom names by first structure order atoms
write_getidx("run.py")
pdbs : Array(String) = [] of String
Dir["#{path}/*.pdb"].each do |pdb|
  st = Chem::Structure.from_pdb(pdb)
  pdbs.push(pdb)
end

puts "Analyzing #{pdbs.size} PDB files"

pdbs.each do |pdb|
  extension = "#{File.extname("#{pdb}")}"
  basename = "#{File.basename("#{pdb}", "#{extension}")}"
  output_pdb = "#{basename}_proc.pdb"
  if File.exists?(output_pdb)
    next
  else
    puts basename
    cmd = "python"
    args = ["run.py", "-a", "#{pdbs[0]}", "-b", "#{pdb}"]
    idxs = run_cmd(cmd, args)
    idxs = idxs.split("\n")
    st_a = Chem::Structure.from_pdb(pdbs[0])
    st_b = Chem::Structure.from_pdb(pdb)
    if st_b.atoms.count(&.heavy?) < st_a.atoms.size
      puts "PDB #{basename}.pdb has fewer atoms than reference. #{st_b.atoms.size}/#{st_a.atoms.size} atoms"
      next
    else
      ordered_atoms = idxs[0..st_a.atoms.size - 1]
      atom_order_map = Hash(String, Int32).new
      ordered_atoms.each_with_index do |name, idx|
        atom_order_map[name] = idx
      end
      sorted_atoms = st_b.atoms.select(&.heavy?).sort_by { |atom| atom_order_map[atom.name] }
      sorted_atoms.to_pdb("#{output_pdb}")
      # selection_a = sorted_atoms.atoms.select(&.heavy?)
      # selection_b = st_b.atoms.select(&.heavy?)
    end
  end
end

# 2. Read all the re-ordered structures as frames

frames : Array(Chem::Structure) = [] of Chem::Structure

Dir["./*_proc.pdb"].each do |pdb|
  st = Chem::Structure.from_pdb(pdb)
  puts st.atoms.count(&.heavy?)
  frames.push(st)
end
structure = frames[0]

puts "Analyzing #{frames.size} processed PDB structures"

dism = HClust::DistanceMatrix.new(frames.size) { |a, b|
  frames[a].pos.rmsd frames[b].pos, minimize: true
}
# ##dendrogram = HClust.linkage(dism, :single)
# ##clusters = dendrogram.flatten(count: n_clusters)
###
# ##centroids = clusters.map do |idxs|
# ##  # puts idxs
# ##  idxs[dism[idxs].centroid]
# ##end
###
# ### Write centroids
# ##count = 0
# ##puts "Centroids:"
# ##centroids.each do |centroid|
# ##  count += 1
# ##  puts "Centroid: #{centroid} RDGYR: #{frames[centroid].pos.rdgyr}"
# ##  frames[centroid].to_pdb("centroid_#{count}.pdb")
# ##end
File.open("#{output_name}.dat", "w") do |log|
  dism.to_a.each do |rmsd|
    log.print("#{rmsd}\n")
  end
end
