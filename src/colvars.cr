record Colvar,
  component : Colvar::Component,
  bounds : Range(Float32, Float32),
  force_constant : Float32,
  width : Float32 do
  def lower_bound : Float32
    @bounds.begin
  end

  def upper_bound : Float32
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
  simulation_time : Float32 = 1.0,
  windows : Int32 = 10 do
  forward_missing_to @colvar

  def total_time : Float32
    @simulation_time * @windows
  end

  def window_bounds : Array(Range(Float32, Float32))
    step = (upper_bound - lower_bound) / @windows
    (0...@windows).map do |i|
      (lower_bound + i * step)..(lower_bound + (i + 1) * step)
    end
  end
end
