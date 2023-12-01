module OpenBabel
  enum CoordinateGenerationMode
    Slowest = 1
    Slow    = 2
    Medium  = 3
    Fast    = 4
    Fastest = 5
  end

  def self.add_hydrogens(path : Path | String) : Chem::Structure
    run(path, {"-h"})
  end

  def self.add_hydrogens(path : Path | String, ph : Float64) : Chem::Structure
    raise ArgumentError.new("Invalid pH #{ph}") unless ph.in?(0..14)
    run(path, {"-p", ph})
  end

  def self.convert(path : Path | String, output : Path | String)
    ::run "obabel", [path, "-O", output]
  end

  def self.convert_smiles(smiles : String) : Chem::Structure
    run("-:#{smiles}", {"-h", "--gen3d"})
  end

  def self.gen_coords(
    path : Path | String,
    mode : CoordinateGenerationMode = :medium
  ) : Chem::Structure
    run(path, {"--gen3d", mode.to_s.downcase}, fail_fast: false)
  end

  def self.run(
    path : Path | String,
    args : Enumerable,
    fail_fast : Bool = true
  ) : Chem::Structure
    tempfile = File.tempfile ".mol"
    cli_args = [path, "-O", tempfile.path]
    args.each { |arg| cli_args << arg.to_s }
    cli_args << "-e" unless fail_fast
    if ::run("obabel", cli_args)
      Chem::Structure.from_mol tempfile.path
    else
      abort "Something went wrong executing `obabel #{cli_args.join(' ')}`"
    end
  ensure
    tempfile.try &.delete
  end
end
