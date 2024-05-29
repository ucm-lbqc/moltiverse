module XTB
  enum OptimizationLevel
    CRUDE
    SLOPPY
    LOOSE
    NORMAL
    TIGHT
    VERY_TIGHT
    EXTREME
  end

  def self.optimize(
    structure : Chem::Structure,
    cycles : Int = 100,
    level : OptimizationLevel = :normal,
    procs : Int = 1
  ) : Chem::Structure?
    tempfile = "xtbinput.pdb"
    structure.to_pdb tempfile
    args = {
      "chrg"   => structure.formal_charge,
      "opt"    => level.to_s.camelcase.downcase,
      "cycles" => cycles,
    }.transform_keys { |k| "--#{k}" }.map(&.to_a).flatten
    run tempfile, args, procs
    if File.exists?("xtbopt.pdb")
      Chem::Structure.from_pdb("xtbopt.pdb")
    else
      STDERR.puts "Something went wrong optimizing #{structure}"
    end
  ensure
    Dir.glob("xtb*") { |path| File.delete path }
  end

  def self.run(
    path : Path | String,
    args : Enumerable,
    procs : Int = 1
  ) : Nil
    cli_args = args.map(&.to_s).push(path)
    ::run("xtb", cli_args, env: {"OMP_NUM_THREADS" => "#{procs},1"})
  end
end
