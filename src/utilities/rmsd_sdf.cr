require "chem"
include Chem
require "option_parser"

def run_cmd(cmd, args)
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(cmd, args: args, output: stdout, error: stderr)
  if status.success?
    stdout.to_s
  else
    stderr.to_s
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

pdbs_path = ""
sdf_file = ""
output_name = "sdf_rmsd"
ref_index = 0

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal rmsd_rdkit.cr [OPTIONS]"
  parser.on("-p PATH", "--pdbs_path=PATH", "Input path for crystalographic reference molecules.") do |str|
    pdbs_path = str
  end
  parser.on("-s FILE", "--sdf_file=FILE", "sdf file that contains the conformers.") do |str|
    sdf_file = str
  end
  parser.on("-r INT", "--ref_index=INT", "index of the SDF to take as reference. Default 0") do |str|
    ref_index = str.to_i32
  end
  parser.on("-o NAME", "--output_name=NAME", "Output folder name. Default: sdf_rmsd") do |str|
    output_name = str
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

write_getidx("run.py")

sdf_structures = Array(Chem::Structure).from_sdf("#{sdf_file}")
sdf_first = sdf_structures[ref_index]
sdf_first.to_pdb("ref.pdb", bonds: :none)
order_ref = Chem::Structure.from_pdb("ref.pdb")

File.open("#{output_name}", "w") do |log|
  Dir["#{pdbs_path}/*.pdb"].each do |pdb|
    file = Path.new(pdb).expand.to_s
    extension = "#{File.extname("#{file}")}"
    format = "#{extension.split(".")[1]}"
    basename = "#{File.basename("#{file}", "#{extension}")}"
    st_pdb = Chem::Structure.from_pdb(pdb)
    cmd = "python"
    args = ["run.py", "-a", "ref.pdb", "-b", "#{file}"]
    idxs = run_cmd(cmd, args)
    idxs = idxs.split("\n")
    # puts idxs.size
    ordered_atoms = idxs[0..st_pdb.atoms.size - 1]
    atom_order_map = Hash(String, Int32).new
    ordered_atoms.each_with_index do |name, idx|
      atom_order_map[name] = idx
    end
    # puts "Number of common atoms: #{ordered_atoms.size}"
    if st_pdb.atoms.count(&.heavy?) == order_ref.atoms.count(&.heavy?) && atom_order_map.size == order_ref.atoms.count(&.heavy?)
      begin
        sorted_atoms = st_pdb.atoms.select(&.heavy?).sort_by { |atom| atom_order_map[atom.name] }
      rescue exception
        puts "Jumping #{basename}. Structure Issues in atom name"
        next
      end
      selection_pdb = sorted_atoms.select(&.heavy?)
    else
      puts "Jumping #{basename}. Structure Issues."
      next
    end

    rmsd = 99999
    sdf_structures.map_with_index do |_, idx|
      st = sdf_structures[idx]
      selection_st = st.atoms.select(&.heavy?)
      rmsd_tmp = selection_pdb.pos.rmsd(selection_st.pos, minimize: true)
      if rmsd_tmp < rmsd
        rmsd = rmsd_tmp
      end
    end
    log.print("#{basename},#{rmsd}\n")
  end
end
