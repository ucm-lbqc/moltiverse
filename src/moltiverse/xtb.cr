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
    cwd = Path[Dir.current]
    input = "xtbinput.pdb"
    output = "xtbopt.pdb"
    structure.to_pdb input
    args = {
      "chrg"   => structure.formal_charge,
      "opt"    => level.to_s.camelcase.downcase,
      "cycles" => cycles,
    }.transform_keys { |k| "--#{k}" }.map(&.to_a).flatten
    run input, args, procs
    if File.exists?(cwd / output)
      Chem::Structure.from_pdb cwd / output
    else
      STDERR.puts "Something went wrong optimizing #{structure}"
    end
  ensure
    cwd = cwd.not_nil!
    Dir.glob(cwd / "xtb*") { |path| File.delete path }
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
