if !@isdefined TEST
    using Revise
end
using Mitosis
using Random, Test, LinearAlgebra, Statistics

# Define some vectors and matrices
ξ0 = [1., 0.]
x = [1.2, 0.1]
P0 = Matrix(1.0I, 2, 2)

Φ = [0.8 0.5; -0.1 0.8]
β = [0.1, 0.2]
Q = [0.2 0.0; 0.0 1.0]

H = [1.0 0.0]
R = Matrix(1.0I, 1, 1)

# and a nonlinear vector function
f(x) = [0.8 0.5; -0.1 0.8]*[atan(x[1]), atan(x[2])] + [0.1, 0.2]

# Define some transition kernels.

# We define the equivalent of the Soss model
:(m = @model ξ0 begin
          x0 ~ MvNormal(ξ0, P0) # priortransition
          y0 ~ MvNormal(H*x0, R) # partialobservation
          x1 ~ MvNormal(f(x0), Q) # nonlineartransition
          y1 ~ MvNormal(H*x1, R) # partial observations
          x2 ~ MvNormal(x1, P0) # full observation
          # return y0, y1, x2
      end;)


# We use AffineMap, LinearMap and ConstantMap
# For example
@test AffineMap(Φ, β)(x) == Φ*x + β

# Prior
# X′ ~ N(X, P0)
fullobservation = priortransition = Mitosis.kernel(Gaussian; μ=LinearMap(I(2)), Σ=ConstantMap(P0))

# Nonlinear transition and linear approximation
# X′ ~ N(f(X), Q)
nonlineartransition = Mitosis.kernel(Gaussian; μ=f, Σ=ConstantMap(Q))
# X′ ~ N(ΦX + β, Q),  with Φ*x + β ≈ f(x)
linearizedtransition = Mitosis.kernel(Gaussian; μ=AffineMap(Φ, β), Σ=ConstantMap(Q))

# Partial observation
# X′ ~ N(H*X, R)
partialobservation = Mitosis.kernel(Gaussian; μ=LinearMap(H), Σ=ConstantMap(R))

# And a deterministic copy kernel
cp2 = Mitosis.Copy{2}() # copy kernel
@test cp2(1.1) == (1.1, 1.1)

# Forward sample a Bayes net
x0 = rand(priortransition(ξ0))
y0 = rand(partialobservation(x0))
            # forward model with nonlinear transition
x1 = rand(nonlineartransition(x0))
y1 = rand(partialobservation(x1))
x2 = rand(fullobservation(x1))


# We actually want to write down the
# forward sample with explicit copies
# so every state is only used as input of a single kernel
x0 = rand(priortransition(ξ0))
x0a, x0b = cp2(x0)
y0 = rand(partialobservation(x0b))
x1 = rand(nonlineartransition(x0a))
x1a, x1b = cp2(x1)
y1 = rand(partialobservation(x1b))
x2 = rand(fullobservation(x1a))

# thus we have obtained some observations
(y0, y1, x2)

# backward steps trace forward step in reverse order
# starting from the observations

m1b, p1b = backward(BFFG(), partialobservation, y1; unfused=true)
m1a, p1a = backward(BFFG(), fullobservation, x2; unfused=true)
m1, p1 = backward(BFFG(), cp2, p1a, p1b) # reverse of copy, call each child transition with unfused=true
m0b, p0b = backward(BFFG(), partialobservation, y0; unfused=true)
            # backward filter just uses linearization
m0a, p0a = backward(BFFG(), linearizedtransition, p1; unfused=true)
m0, p0 = backward(BFFG(), cp2, p0a, p0b)
m, evidence = backward(BFFG(), priortransition, p0) # not a child of copy

# this creates messages m, m0, m1, ... and an evidence approximation

# forward sampler, requires the messages from the previous pass and
# a weighted starting term ξ0

x0 = rand(forward(BFFG(), priortransition, m, weighted(ξ0)))
x0a, x0b = rand(forward(BFFG(), cp2, m0, x0))
y0 = rand(forward(BFFG(), partialobservation, m0b, x0b))
            # guided sampler targets nonlineartransition, needs to know linearizedtransition
x1 = rand(forward(BFFG(), (nonlineartransition, linearizedtransition), m0a, x0a))
x1a, x1b = rand(forward(BFFG(), cp2, m1, x1))
y1 = rand(forward(BFFG(), partialobservation, m1b, x1b))
x2 = rand(forward(BFFG(), fullobservation, m1a, x1a))


# weighted joint posterior sample (x0, x1 random)
(x0, y0, x1, y1, x2)

# final importance weight as sum of weights of _leaves_ of guided pass
# the importance weight accounts for mismatch of linear backward filter
# and nonlinear forward model
w = x2.ll + y1.ll + y0.ll
