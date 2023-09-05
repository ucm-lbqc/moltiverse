module Dependencies
  def dependencies
    dependencies = {
    "obabel"=>true, 
    "namd2"=>true, 
    "rdkit"=>true, 
    "parmed"=>true, 
    "antechamber"=>true, 
    "parmchk2"=>true, 
    "tleap"=>true}

    puts "Checking dependencies..."
    # Openbabel
    begin
      run_cmd(cmd="obabel", args=["-H"], output_file=Nil, stage="openbabel ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["obabel"] = false
      puts "obabel ✘".colorize(RED)
    end

    # Namd
    begin
      run_cmd(cmd="namd2", args=[""], output_file=Nil, stage="namd2 ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["namd2"] = false
      puts "namd2 ✘".colorize(RED)
    end

    # Rdkit in python
    begin
      library = "import importlib;importlib.import_module('rdkit')"
      run_cmd(cmd="python", args=["-c", "#{library}"], output_file=Nil, stage="rdkit ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["rdkit"] = false
      puts "rdkit ✘".colorize(RED)
    end
    # ParmEd in python
    begin
      library = "import importlib;importlib.import_module('parmed')"
      run_cmd(cmd="python", args=["-c", "#{library}"], output_file=Nil, stage="parmed ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["parmed"] = false
      puts "parmed ✘".colorize(RED)
    end

    # Antechamber
    begin
      run_cmd(cmd="antechamber", args=[""], output_file=Nil, stage="antechamber ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["antechamber"] = false
      puts "antechamber ✘".colorize(RED)
    end

    # Parmchk2
    begin
      run_cmd(cmd="parmchk2", args=[""], output_file=Nil, stage="parmchk2 ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["parmchk2"] = false
      puts "parmchk2 ✘".colorize(RED)
    end

    # Tleap
    begin
      run_cmd(cmd="tleap", args=[""], output_file=Nil, stage="tleap ✔".colorize(GREEN), verbose=false)
    rescue exception
      dependencies["tleap"] = false
      puts "tleap ✘".colorize(RED)
    end

    dependencies.each do |key, value|
      if !value
        puts "There are missing dependencies.".colorize(PURPLE)
        puts "Exit".colorize(PURPLE)
        exit(1)
      end
    end
  end
end