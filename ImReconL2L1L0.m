% ImReconL2L1L0 provides a unified optimization framework
%
% recon = ImReconL2L1L0( L2, L1, L0, range, padsize, x0, rho, itr, th, verbose )
%
%Output arguments:
% recon: reconstructed image
%
%Input arguments:
% L2: cell list for L2 norm functions
% L1: cell list for L1 norm functions
% L0: cell list for L0 norm functions
% range: intensity range (default: [-inf, inf])
% padsize: padding size (ex. [18, 18])
% x0: initial image 
% rho: parameter for the ADMM (default: 1)
% itr: max iteration number (default: 128)
% th: stoping critera (default: 1E-3)
% verbose: 0:silent, 1:print information (default: 0)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                          %
% Copyright (C) 2017                                       %
%                    Masayuki Tanaka. All rights reserved. %
%                    mtanaka@sc.e.titech.ac.jp             %
%                                                          %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function recon = ImReconL2L1L0( L2, L1, L0, range, padsize, x0, rho, itr, th, verbose )

if( ~exist('verbose', 'var') || isempty(verbose) )
 verbose = 0;
end

if( ~exist('rho', 'var') || isempty(rho) )
 rho = 1;
end

if( ~exist('range', 'var') || isempty(range) )
 range = [-inf,inf];
end

if( ~exist('itr', 'var') || isempty(itr) )
 itr = 128;
end

if( ~exist('th', 'var') || isempty(th) )
 th = 1E-3;
end

L2num = numel(L2);
L1num = numel(L1);
L0num = numel(L0);
num = L2num+L1num+L0num+1;

h = size(L2{1}.y, 1) + 2*padsize(1);
w = size(L2{1}.y, 2) + 2*padsize(2);
cha = size(L2{1}.y,3);

Ys = zeros( h, w, cha, num );
Ks = zeros( h, w, 1, num );
Lambdas = zeros( num, 1);

if( exist('x0', 'var') )
    recon = PaddingSmCircular( x0, padsize );
else
    if( numel( range ) == 2 )
        recon = ones( h, w ) * ( range(1) + range(2) ) / 2;
    else
        recon = ( range(:,:,1) + range(:,:,2) ) / 2;
        recon = PaddingSmCircular( recon, padsize );
    end
end


L1z = zeros( h, w, cha, L1num );
L1u = zeros( h, w, cha, L1num );

L0z = zeros( h, w, cha, L0num );
L0u = zeros( h, w, cha, L0num );

Rgz = zeros( h, w, cha );
Rgu = zeros( h, w, cha );

p = 1;

for i=1:L2num
 for j=1:cha
  padded = PaddingSmCircular( L2{i}.y(:,:,j), padsize );
  Ys(:,:,j,p) = fft2( padded );
 end
 
 Ks(:,:,1,p) = fft2ker( flipker( L2{i}.k ), [h w] );
 Lambdas(p) = L2{i}.lambda;
 p = p + 1;
end

L1padded = cell(L1num,1);
for i=1:L1num
 if( isfield( L1{i}, 'y' ) )
  L1padded{i} = PaddingSmCircular( L1{i}.y, padsize );
 else
  L1padded{i} = zeros( h, w, cha );
  L1{i}.y = zeros(size(L2{1}.y));
 end
 Ks(:,:,1,p) = fft2ker( flipker( L1{i}.k ), [h w] );
 Lambdas(p) = rho/2;
 p = p + 1;
end

L0padded = cell(L0num,1);
for i=1:L0num
 if( isfield( L0{i}, 'y' ) )
  L0padded{i} = PaddingSmCircular( L0{i}.y, padsize );
 else
  L0padded{i} = zeros( h, w, cha );
  L0{i}.y = zeros(size(L2{1}.y));
 end
 Ks(:,:,1,p) = fft2ker( flipker( L0{i}.k ), [h w] );
 Lambdas(p) = rho/2;
 p = p + 1;
end

Ks(:,:,1,p) = fft2ker( 1, [h w] );
Lambdas(p) = rho/2;

L = reshape( Lambdas, [1,1,1,num] );
L = repmat( L, [h,w] );
LCKs = L .* conj(Ks);

cost = inf;
for it=1:itr

 recon = UpdatingSmCircular( recon, padsize );
 for i=1:L1num
  Kx = imfilter( recon, L1{i}.k, 'circular' );

   L1z(:,:,:,i) = proxL1( Kx - L1padded{i} + L1u(:,:,:,i), rho/L1{i}.lambda );
   L1u(:,:,:,i) = L1u(:,:,:,i) + Kx - L1padded{i} - L1z(:,:,:,i); 
 end
 
 for i=1:L0num
  Kx = imfilter( recon, L0{i}.k, 'circular' );

  L0z(:,:,:,i) = proxL0( Kx - L0padded{i} + L0u(:,:,:,i), rho/L0{i}.lambda );
  L0u(:,:,:,i) = L0u(:,:,:,i) + Kx - L0padded{i} - L0z(:,:,:,i);
 end

 Rgz = proxRange( recon + Rgu, range );
 Rgu = Rgu + recon - Rgz;
 
 p = L2num+1;
 for i=1:L1num
  for j=1:cha
   Ys(:,:,j,p) = fft2( L1z(:,:,j,i) + L1padded{i}(:,:,j) - L1u(:,:,j,i) );
  end
  p = p + 1;
 end
 for i=1:L0num
  for j=1:cha
   Ys(:,:,j,p) = fft2( L0z(:,:,j,i) + L0padded{i}(:,:,j) - L0u(:,:,j,i) );
  end
  p = p + 1;
 end
 
 for j=1:cha
  Ys(:,:,j,p) = fft2( Rgz(:,:,j) - Rgu(:,:,j) );
 end
 
 R = SolveQFormFreq( Ks, LCKs, Ys );
 recon = real(ifft2( R ));

 urecon = UnPadding( recon, padsize );
 cost0 = cost;
 cost = costEvaluation(urecon, L2, L1, L0);
 
 if( verbose > 0 )
  fprintf('%03d %g\n', it, cost );
 end
 
 if( abs(cost0-cost)/cost0 < th )
    break;
 end
 
end

recon = UnPadding( recon, padsize );

end



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function cost = costEvaluation(x, L2, L1, L0)

cost = 0;

for i=1:numel(L2)
 kx = imfilter( x, L2{i}.k, 'replicate' );
 dif = L2{i}.y - kx;
 dif = dif .* dif;
 cost = cost + L2{i}.lambda * sum(dif(:));
end

for i=1:numel(L1)
 kx = imfilter( x, L1{i}.k, 'replicate' );
 dif = L1{i}.y - kx;
 dif = abs(dif);
 cost = cost + L1{i}.lambda * sum(dif(:));
end

for i=1:numel(L0)
 kx = imfilter( x, L0{i}.k, 'replicate' );
 dif = L0{i}.y - kx;
 dif = double( dif ~= 0);
 cost = cost + L0{i}.lambda * sum(dif(:));
end

cost = cost / numel(x);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function X = SolveQFormFreq( Ks, LCKs, Ys )

s = size(Ys);
X = zeros(s(1), s(2), s(3));

for j=1:s(3)

 K2 = LCKs .* Ks;
 K2 = sum( K2, 4 );

 YK = LCKs .* Ys(:,:,j,:);
 YK = sum( YK, 4 );

 X(:,:,j) = YK ./ K2;

end

end
