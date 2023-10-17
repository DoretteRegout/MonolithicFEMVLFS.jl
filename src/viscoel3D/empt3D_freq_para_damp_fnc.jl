module Memb3D

using Revise
using Gridap
using Parameters
using Plots
using DrWatson
using WaveSpec
using .Constants
using TickTock
using DataFrames


function main(params)

  function run_freq(ω, η₀)

    tick()

    # Wave parameters
    k = dispersionRelAng(H0, ω; msg = false)
    λ = 2*π/k
    T = 2π/ω
    ηᵢₙ(x) = η₀*exp(im*k*x[1])
    ϕᵢₙ(x) = -im*(η₀*ω/k)*(cosh(k*(H0 + x[3])) / sinh(k*H0))*exp(im*k*x[1])
    vxᵢₙ(x) = (η₀*ω)*(cosh(k*(H0 + x[3])) / sinh(k*H0))*exp(im*k*x[1])
    vzfsᵢₙ(x) = -im*ω*η₀*exp(im*k*x[1]) #???
    @show ω, T
    @show λ
    @show η₀
    @show H0, H0/λ

    # Numeric constants
    αₕ = -im*ω/g * (1-βₕ)/βₕ
    @show αₕ
    println()

    # Damping
    μ₀ = 2.5
    μ₁ᵢₙ(x) = μ₀*(1.0 - sin(π/2*(x[1]-x₀)/Ld))
    μ₁ₒᵤₜ(x) = μ₀*(1.0 - cos(π/2*(x[1]-xdₒₜ)/Ld))
    μ₂ᵢₙ(x) = μ₁ᵢₙ(x)*k
    μ₂ₒᵤₜ(x) = μ₁ₒᵤₜ(x)*k
    ηd(x) = μ₂ᵢₙ(x)*ηᵢₙ(x)
    ∇ₙϕd(x) = μ₁ᵢₙ(x)*vzfsᵢₙ(x) #???


    # Weak form
    ∇ₙ(ϕ) = ∇(ϕ)⋅VectorValue(0.0,0.0,1.0)  
    a((ϕ,κ),(w,u)) =      
      ∫(  ∇(w)⋅∇(ϕ) )dΩ   +
      ∫(  βₕ*(u + αₕ*w)*(g*κ - im*ω*ϕ) + im*ω*w*κ )dΓfs   +
      ∫(  βₕ*(u + αₕ*w)*(g*κ - im*ω*ϕ) + im*ω*w*κ 
        - μ₂ᵢₙ*κ*w + μ₁ᵢₙ*∇ₙ(ϕ)*(u + αₕ*w) )dΓd1    +
      # ∫( -w * im * k * ϕ )dΓot +
      ∫(  βₕ*(u + αₕ*w)*(g*κ - im*ω*ϕ) + im*ω*w*κ 
        - μ₂ₒᵤₜ*κ*w + μ₁ₒᵤₜ*∇ₙ(ϕ)*(u + αₕ*w) )dΓd2    #+
      # ∫(  v*(g*η - im*ω*ϕ) +  im*ω*w*η
      #   - mᵨ*v*ω^2*η + Tᵨ*(1-im*ω*τ)*∇(v)⋅∇(η) )dΓm  #+ 
      #∫(- Tᵨ*(1-im*ω*τ)*v*∇(η)⋅nΛmb )dΛmb #diri

    l((w,u)) =  ∫( w*vxᵢₙ )dΓin - ∫( ηd*w - ∇ₙϕd*(u + αₕ*w) )dΓd1


    println("[MSG] Formulation complete")

    # Solution
    op = AffineFEOperator(a,l,X,Y)
    (ϕₕ,κₕ) = solve(op)
        

    # Wave energy flux
    kh = k*H0
    wave_n = 0.5*(1 + 2*kh/sinh(2*kh))
    Pin = (0.5*ρw*g*η₀*η₀)*(ω/k)*wave_n*Wm

    # Wave energy flux measured
    κm = κₕ(Point(xm₀, 0.0, 0.0))
    Pinm = (0.5*ρw*g*conj(κm)*κm)*(ω/k)*wave_n*Wm

    push!(prbPow, [ω, Pin, Pinm, κm])

    println("Power In \t ",Pin," W")    
    println("Power In Measured \t ",Pinm," W")
    println("κ In Measured \t ",abs(κm)," W")
    tock()
    println("----------")
    println()
    return 0
  end

  @unpack name, order, vtk_output = params
  filename = name*"/mem"

  ρw = 1025 #kg/m3 water
  @unpack H0 = params #m #still-water depth
  @show H0

  # Membrane parameters
  @unpack Lm, Wm, mᵨ, Tᵨ, τ = params
  @show Lm  #m
  @show Wm  #m
  @show g   #defined in .Constants
  @show mᵨ  #mass per unit area of membrane / ρw
  @show Tᵨ  #T/ρw
  @show τ   #damping coeff

  # Wave parameters
  @unpack ω, η₀ = params
  @show ω 
  @show η₀  
  @show H0
  println()


  # Domain 
  @unpack nx, ny, nz, mesh_rz, Ld, LΩ, WΩ, x₀ = params
  @unpack domain, partition, xdᵢₙ, xdₒₜ, xm₀, xm₁, ym₀, ym₁ = params
  @show Lm
  @show LΩ
  @show domain
  @show partition
  @show (xm₀, xm₁) (ym₀, ym₁)
  @show isinteger(Lm/LΩ*nx)
  @show LΩ/nx
  @show H0/nz
  println()


  # Numeric constants
  h = LΩ / nx
  γ = 1.0*order*(order-1)/h
  βₕ = 0.5
  @show h
  @show βₕ  
  println()


  # Mesh
  function f_z(z, r, n, H0; dbgmsg = false)
    # Mesh along depth as a GP
    # Depth is 0 to -H0    
    if(r ≈ 1.0)
      return z 
    else
      a0 = H0 * (r-1) / (r^n - 1)    
      if(dbgmsg)
        ln = 0:n
        lz = -a0 / (r-1) * (r.^ln .- 1)         
        @show hcat( lz, [ 0; lz[1:end-1] - lz[2:end] ] )
      end
      
      if z ≈ 0
        return 0.0
      end
      j = abs(z) / H0 * n  
      return -a0 / (r-1) * (r^j - 1)
    end
  end
  map(x) = VectorValue( x[1], x[2], f_z(x[3], 
    mesh_rz, nz, H0; dbgmsg=false) )
  model = CartesianDiscreteModel(domain,partition,map=map)


  # Labelling
  labels_Ω = get_face_labeling(model)
  add_tag_from_tags!(labels_Ω,"surface",
    [5,6,7,8,11,12,15,16,22])   
  add_tag_from_tags!(labels_Ω,"bottom",
    [1,2,3,4,9,10,13,14,21])
  add_tag_from_tags!(labels_Ω,"inlet",
    [17,19,25]) 
  add_tag_from_tags!(labels_Ω,"outlet",
    [18,20,26])   
  add_tag_from_tags!(labels_Ω,"swNear",
    [23])   
  add_tag_from_tags!(labels_Ω,"swFar",
    [24])   

  # Triangulations
  Ω = Interior(model) #same as Triangulation()
  Γ = Boundary(model,tags="surface") #same as BoundaryTriangulation()
  Γin = Boundary(model,tags="inlet")
  Γot = Boundary(model,tags="outlet")

  # Auxiliar functions
  function is_mem(xs) # Check if an element is inside the beam1
    n = length(xs)
    x = (1/n)*sum(xs)
    (xm₀ <= x[1] <= xm₁ ) * (ym₀ <= x[2] <= ym₁) * ( x[3] ≈ 0.0)
  end
  function is_damping1(xs) # Check if an element is inside the damping zone 1
    n = length(xs)
    x = (1/n)*sum(xs)
    (x₀ <= x[1] <= xdᵢₙ ) * ( x[3] ≈ 0.0)
  end
  function is_damping2(xs) # Check if an element is inside the damping zone 2
    n = length(xs)
    x = (1/n)*sum(xs)
    (xdₒₜ <= x[1] ) * ( x[3] ≈ 0.0)
  end

  # Masking and Beam Triangulation
  xΓ = get_cell_coordinates(Γ)
  # Γm_to_Γ_mask = lazy_map(is_mem, xΓ)
  Γd1_to_Γ_mask = lazy_map(is_damping1, xΓ)
  Γd2_to_Γ_mask = lazy_map(is_damping2, xΓ)
  # Γm = Triangulation(Γ, findall(Γm_to_Γ_mask))
  Γd1 = Triangulation(Γ, findall(Γd1_to_Γ_mask))
  Γd2 = Triangulation(Γ, findall(Γd2_to_Γ_mask))
  Γfs = Triangulation(Γ, findall(!, Γd1_to_Γ_mask .| Γd2_to_Γ_mask))
  # Γη = Triangulation(Γ, findall(Γm_to_Γ_mask))
  Γκ = Γ


  # # Construct the tag for membrane boundary
  # Λmb = Boundary(Γm)
  # xΛmb = get_cell_coordinates(Λmb)
  # xΛmb_n1 = findall(model.grid_topology.vertex_coordinates .== xΛmb[1])
  # xΛmb_n2 = findall(model.grid_topology.vertex_coordinates .== xΛmb[2])
  # new_entity = num_entities(labels_Ω) + 1
  # labels_Ω.d_to_dface_to_entity[1][xΛmb_n1[1]] = new_entity
  # labels_Ω.d_to_dface_to_entity[1][xΛmb_n2[1]] = new_entity
  # add_tag!(labels_Ω, "mem_bnd", [new_entity])


  writevtk(model, filename*"_model")
  if vtk_output == true
    writevtk(Ω,filename*"_O")
    writevtk(Γ,filename*"_G")
    # writevtk(Γm,filename*"_Gm")  
    writevtk(Γd1,filename*"_Gd1")
    writevtk(Γd2,filename*"_Gd2")
    writevtk(Γfs,filename*"_Gfs")
    # writevtk(Λmb,filename*"_Lmb")  
  end


  # Measures
  degree = 2*order
  dΩ = Measure(Ω,degree)
  # dΓm = Measure(Γm,degree)
  dΓd1 = Measure(Γd1,degree)
  dΓd2 = Measure(Γd2,degree)
  dΓfs = Measure(Γfs,degree)
  dΓin = Measure(Γin,degree)
  dΓot = Measure(Γot,degree)
  # dΛmb = Measure(Λmb,degree)


  # # Normals
  # @show nΛmb = get_normal_vector(Λmb)


  # Dirichlet Fnc
  gη(x) = ComplexF64(0.0)

  # FE spaces
  reffe = ReferenceFE(lagrangian,Float64,order)
  V_Ω = TestFESpace(Ω, reffe, conformity=:H1, 
    vector_type=Vector{ComplexF64})
  V_Γκ = TestFESpace(Γκ, reffe, conformity=:H1, 
    vector_type=Vector{ComplexF64})  
  # V_Γη = TestFESpace(Γη, reffe, conformity=:H1, 
  #     vector_type=Vector{ComplexF64})
  U_Ω = TrialFESpace(V_Ω)
  U_Γκ = TrialFESpace(V_Γκ)
  # U_Γη = TrialFESpace(V_Γη)
  # X = MultiFieldFESpace([U_Ω,U_Γκ,U_Γη])
  # Y = MultiFieldFESpace([V_Ω,V_Γκ,V_Γη])  
  X = MultiFieldFESpace([U_Ω,U_Γκ])
  Y = MultiFieldFESpace([V_Ω,V_Γκ])  

  # Power probes
  prbPow = DataFrame(zeros(ComplexF64, 1, 4), :auto)

  # Run weak-form for each freq
  run_freq.(ω, η₀)

  prbPow = prbPow[2:end,:]

  k = dispersionRelAng.(H0, ω; msg=false)
  data = Dict("ω" => ω,
              "η₀" => η₀,
              "k" => k,
              "prbPow" => prbPow)

  wsave(filename*"_data.jld2", data)
end


"""
Memb_params

Parameters for the VIV.jl module.
"""
@with_kw struct Memb_params
  name::String = "data/sims_202309/run/mono3D_freq_free"
  order::Int = 2
  vtk_output::Bool = true

  H0 = 10 #m #still-water depth

  # Membrane parameters
  Lm = 2*H0 #m
  Wm = Lm  
  mᵨ = 0.9 #mass per unit area of membrane / ρw
  Tᵨ = 0.1/4*g*Lm*Lm #T/ρw
  τ = 0.0#damping coeff

  # Wave parameters
  ω = 1:1:2
  T = 2*π./ω
  η₀ = 0.10*ones(length(ω))
  # α = randomPhase(ω; seed=100)

  # Domain 
  nx = 50
  ny = 4
  nz = 3
  mesh_rz = 1.2 #Ratio for Geometric progression of eleSize
  # Ld = 9*H0 #damping zone length
  # LΩ = 5*Lm + 2*Ld
  Ld = 6*H0 #damping zone length
  LΩ = 4*Lm + 2*Ld
  WΩ = 4*H0
  x₀ = -Ld
  domain =  (x₀, x₀+LΩ, -WΩ/2, WΩ/2 , -H0, 0.0)
  partition = (nx, ny, nz)
  xdᵢₙ = 0.0
  xdₒₜ = x₀ + LΩ - Ld
  xm₀ = xdᵢₙ + 1.5*Lm
  xm₁ = xm₀ + Lm
  ym₀ = -Wm/2
  ym₁ = Wm/2

end


end