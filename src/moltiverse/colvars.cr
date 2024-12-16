require "yaml"

class Colvar
  include YAML::Serializable

  property component : Colvar::Component
  property lower_bound : Float64
  property upper_bound : Float64
  property force_constant : Float64
  property bin_width : Float64

  def initialize(
    @component : Colvar::Component,
    @lower_bound : Float64,
    @upper_bound : Float64,
    @bin_width : Float64,
    @force_constant : Float64
  )
    if @lower_bound > @upper_bound
      raise ArgumentError.new("Lower bound is greater than upper bound")
    end
  end

  def bounds : Range(Float64, Float64)
    @lower_bound..@upper_bound
  end
end

abstract struct Colvar::Component
  include YAML::Serializable

  use_yaml_discriminator "type", {rmsd: RMSD, rdgyr: RadiusOfGyration}

  def initialize
  end

  def keyword : String
    # name.camelcase(lower: true)
    name.upcase
  end

  def name : String
    self.class.name.rpartition("::").last
  end
end

struct Colvar::RMSD < Colvar::Component; end

struct Colvar::RadiusOfGyration < Colvar::Component
  def keyword : String
    "gyration"
  end
end

class Colvar::Windowed < Colvar
  property windows : Int32 = 10

  def initialize(
    @component : Colvar::Component,
    @lower_bound : Float64,
    @upper_bound : Float64,
    @bin_width : Float64,
    @windows : Int32 = 10,
    @force_constant : Float64 = 20
  )
  end

  def window_colvars : Array(Colvar)
    (0...@windows).map do |i|
      lower_bound = @lower_bound + i * window_width
      upper_bound = lower_bound + window_width
      Colvar.new @component, lower_bound, upper_bound, @bin_width, @force_constant
    end
  end

  def window_width : Float64
    (@upper_bound - @lower_bound) / @windows
  end
end
