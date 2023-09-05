module Analysis
  def n_frames(pdb : String, dcd : String)
    structure = Chem::Structure.from_pdb(pdb)
    Chem::DCD::Reader.open((dcd), structure) do |reader|
      n_frames = reader.n_entries - 1
    end
  end
end