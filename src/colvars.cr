record Colvar,
  component : Colvar::Component,
  bounds : Range(Float64, Float64),
  force_constant : Float64,
  width : Float64 do
  def lower_bound : Float64
    @bounds.begin
  end

  def upper_bound : Float64
    @bounds.end
  end
end

abstract struct Colvar::Component
  def name : String
    self.class.name.rpartition("::").last
  end
end

struct Colvar::RMSD < Colvar::Component; end

struct Colvar::RadiusOfGyration < Colvar::Component; end

record Colvar::Sampling,
  colvar : Colvar,
  simulation_time : Float64 = 1.0,
  windows : Int32 = 10 do
  forward_missing_to @colvar

  def total_time : Float64
    @simulation_time * @windows
  end

  def window_bounds : Array(Range(Float64, Float64))
    step = (upper_bound - lower_bound) / @windows
    (0...@windows).map do |i|
      (lower_bound + i * step)..(lower_bound + (i + 1) * step)
    end
  end
end
