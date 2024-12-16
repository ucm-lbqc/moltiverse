require "./spec_helper"

describe SamplingProtocol do
  it "creates from YAML" do
    protocol = File.open("#{__DIR__}/../data/c1.yml") do |io|
      SamplingProtocol.from_yaml io
    end
    protocol.colvars.size.should eq 1
    protocol.colvars[0].should be_a Colvar::Windowed
    protocol.colvars[0].component.should be_a Colvar::RadiusOfGyration
    protocol.colvars[0].bounds.should eq 3..9
    protocol.colvars[0].bin_width.should eq 0.05
    protocol.colvars[0].windows.should eq 12
    protocol.colvars[0].force_constant.should eq 10
    protocol.simulation_time.should eq 2
    protocol.fullsamples.should eq 250
    protocol.metadynamics.should be_true
    protocol.hillweight.should eq 3
    protocol.hillwidth.should eq 3
    protocol.newhillfrequency.should eq 50
    protocol.n_variants.should eq 1
    protocol.output_frequency.should eq 400
  end
end
