class Colvar
  property component : Colvar::Component
  property bounds : Range(Float64, Float64)
  property force_constant : Float64
  property width : Float64

  def initialize(
    @component : Colvar::Component,
    @bounds : Range(Float64, Float64),
    @force_constant : Float64,
    @width : Float64
  )
  end

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

class Colvar::Windowed < Colvar
  property windows : Int32 = 10

  def initialize(
    @component : Colvar::Component,
    @bounds : Range(Float64, Float64),
    @windows : Int32 = 10,
    @force_constant : Float64 = 20
  )
    @width = (@bounds.end - @bounds.begin) / @windows
  end

  def window_bounds : Array(Range(Float64, Float64))
    step = (upper_bound - lower_bound) / @windows
    (0...@windows).map do |i|
      (lower_bound + i * step)..(lower_bound + (i + 1) * step)
    end
  end
end
