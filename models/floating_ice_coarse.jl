using Gridap
using Gridap.Io
using GridapGmsh


# if GridapGmsh.gmsh.isInitialized()
  # GridapGmsh.gmsh.finalize()
# end
# infilename = joinpath(@__DIR__,"floating_ice_coarse.msh")
# outfilename = joinpath(@__DIR__,"floating_ice_coarse.json")
infilename = joinpath(@__DIR__,"floating_ice_modified2_step50.msh")
outfilename = joinpath(@__DIR__,"floating_ice_modified2_step50.json")
model = GmshDiscreteModel(infilename)
to_json_file(model,outfilename)