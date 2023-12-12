module Freq_time

using DrWatson
@quickactivate "Offshore PV"

using DataFrames
using Plots
using Statistics
using TimerOutputs
using Interpolations
using TickTock
using CSV
export freq_time_trans




#This file contains a function, which takes the DataframeRow as input and a random spectrum also stored in a Dataframe as an input
#Output is a time solution for θ
#Output is a DataFrame containing all the variations of parameters in the rows, while the different columns represent diffrent input spectrum


function freq_time_trans(rao::DataFrameRow, spectrum, Hs, Tp; time_steps = 0.25 ,seconds::Int64 =1200) #rao should be a DataFrameRow
    
    #rao is the response amplitude function for a constant wavespectrum A = 1 and intial phaseshift = 0 
    
    ω = spectrum[!,"frequency"]
    k = spectrum[!,"wavenumber"]
    A = spectrum[!,"amplitude"]
    λ = spectrum[!, "wavelength"]
    α = spectrum[!, "phaseshift"]

    slope_spectrum = (2* π * A) ./ λ      #Wave Height over wave length

    RAO_η  = rao["RAO_η"] 
    RAO_ηx = rao["RAO_ηx"]
    ϕ_η = rao["η_ϕ"]
    ϕ_ηx = rao["ηₓ_ϕ"]   

    ω_org = rao["omega"]  #contains the omega with the old step size
    ω_org = repeat(ω_org, 1, size(RAO_ηx)[2])
    #RAOs need to be interpolated 

    xi = range(0, 2*pi*2, 2401)[40:1910] #Nw 2401 between 0 and 2*pi*2hz -> just take values between 0.2 and 10 rad/s
    RAOη_new = zeros(length(xi) ,size(RAO_η)[2])
    RAOηx_new = zeros(length(xi) ,size(RAO_ηx)[2])
    ϕ_η_new = zeros(length(xi) ,size(ϕ_η)[2])
    ϕ_ηx_new = zeros(length(xi) ,size(ϕ_ηx)[2])

    tick()
    for i in 1:(size(RAOη_new)[2])
        inter_η = linear_interpolation(ω_org[:,i], RAO_η[:,i],extrapolation_bc = Line())
        RAOη_new[:,i] = inter_η(xi)
        inter_ηx = linear_interpolation(ω_org[:,i], RAO_ηx[:,i],extrapolation_bc = Line())
        RAOηx_new[:,i] = inter_ηx(xi)
        inter_ϕ_η = linear_interpolation(ω_org[:,i], ϕ_η[:,i],extrapolation_bc = Line())
        ϕ_η_new = inter_ϕ_η(xi)
        inter_ϕ_ηx = linear_interpolation(ω_org[:,i], ϕ_ηx[:,i],extrapolation_bc = Line())
        ϕ_ηx_new = inter_ϕ_ηx(xi)
    end
    tock()
    #From now on the RAO have more rows, columns represent the postions
    #Overwrite to not change the code
    #RAO_η = RAOη_new
    #RAO_ηx = RAOηx_new

    println(size(RAO_ηx))
    
    A = repeat(A,1,size(RAOη_new)[2])
    slope_spectrum = repeat(slope_spectrum,1,size(RAOηx_new)[2])
    k = repeat(k,1,size(RAOη_new)[2])
    ω = repeat(ω,1,size(RAOη_new)[2])
    α = repeat(α,1,size(RAOη_new)[2])


    println(size(A))
    elevation_amp = A .* RAOη_new 
    elevation_angle = ϕ_η_new .+ α

    slope_amp = slope_spectrum .* RAOηx_new
    slope_angle = ϕ_ηx_new .+ α
    
  
    #Functions to calculate the sume  
    fourier_η(t) =  sum(elevation_amp .* sin.(ω*t.+ elevation_angle),dims=1) #function to sum up all fourier parts for every point for a specific time
    #fourier_ηᵪ(x) = sum(slope_amp .* sin.(ω*x-k * x .+ slope_angle),dims=1)
    fourier_ηᵪ(x) = sum(slope_amp .* sin.(ω*x .+ slope_angle),dims=1) #right formulation

    time_points = collect(0:time_steps:seconds)
    vec(time_points)

    # η = vcat(fourier_η.(time_points)...) #not really needed
    ηₓ= vcat(fourier_ηᵪ.(time_points)...)

    θ_points = atan.(ηₓ)*180/π #transform to degrees
    
    # θ_points = η
    θ = ones(length(time_points),size(RAOη_new)[2]-1)

    for i in 1:(size(RAOη_new)[2]-1)
        θ[:,i] = (θ_points[:,i] .+ θ_points[:,i+1]) ./ 2 #average the tilt between to points
    end

    Df_time = DataFrame("seconds" => time_points)
    #Df_η    = DataFrame(η,:auto)
    
    Df_θ    = DataFrame(θ,:auto)
    
    #calculate statistical values

    Df_mean_θ = mean.(eachcol(Df_θ))
    Df_std_θ = [std(Df_θ[!,col], corrected = true) for col in names(Df_θ)]


    θ_time = [Df_time Df_θ]
    #η_time = [Df_time Df_η]

    rao = hcat(DataFrame(rao), [θ_time])
    rename!(rao, :x1 => :theta_time)
    #rao = hcat(DataFrame(rao), [η_time])
    #rename!(rao, :x1 => :η_time)
    rao = hcat(DataFrame(rao), [Df_mean_θ])
    rename!(rao, :x1 => :theta_mean)
    rao = hcat(DataFrame(rao), [Df_std_θ])
    rename!(rao, :x1 => :theta_std)


    rao = select!(rao, Not([:amplitude, :omega, :length_beam, :RAO_ηx, :RAO_η, :η_ϕ, :ηₓ_ϕ,  :phase, :path ]))
    
    rao_dict = Dict("material" => rao.material[1],
                    "h_b" => rao.h_b[1],
                    "theta_time" => rao.theta_time[1],
                    "theta_mean" => rao.theta_mean[1],
                    "theta_std" => rao.theta_std[1],
                    "mesh_size" => rao.mesh_size
                    )
    
    theta_dict = Dict("material" => rao.material[1],
                        "h_b" => rao.h_b[1],
                        "theta" => θ)
                        
     
    println("THETA")
    save_df_theta = DataFrame(zeros(4801,202), :auto)
    rename!(save_df_theta, :x1 => :h_b)
    rename!(save_df_theta, :x2 => :material)
    new_names = Symbol.("theta_x" .* string.(3:202))
    rename!(save_df_theta, names(save_df_theta)[3:202] .=> new_names)

    
    save_df_theta[!,"h_b"] .= rao.h_b[1]
    save_df_theta[!,"material" ] .= rao.material[1]
    save_df_theta[!,3:end] = θ
    
    filepath = "pp = " * string(Tp) *" Hs = "*string(Hs)
    #Mac
    filename = "/aaa_time results mat_" * rao.material[1] *
        "_hb_"*string(rao.h_b[1]) * "_numFloat_"*string(rao.numFloat[1])
    # filename = "/aaa_time results mat_" * rao.material[1] *
    #     "_hb_"*string(rao.h_b[1])
    #PC
    #filename = "\\time results mat_" * rao.material[1] * "_hb_"*string(rao.h_b[1])
    #Mac
    CSV.write(datadir("sims_202311")*"/"*filepath*filename *".csv", save_df_theta; delim = ';')
    #PC
    #CSV.write("C:\\Users\\phili\\iCloudDrive\\Studium\\Thesis\\sims\\CSV time simulation\\" * filepath *  filename *".csv", save_df_theta; delim = ';')

    

    #if you return the RAO_dict, you can use it in the "Initialize_freq_time",
    #but I just used to save the CSV file directly here and not use the dict. 
    return rao_dict
end










end
