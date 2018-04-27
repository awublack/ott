classdef TmatrixEbcm < ott.Tmatrix
%TmatrixEbcm constructs a T-matrix using extended boundary conditions method
%
% TmatrixEbcm properties:
%   k_medium          Wavenumber in the surrounding medium
%   k_particle        Wavenumber of the particle
%
% This class is based on tmatrix_ebcm_axisym.m from ottv1.
%
% This file is part of the optical tweezers toolbox.
% See LICENSE.md for information about using/distributing this file.

  properties (SetAccess=protected)
    k_medium            % Wavenumber of medium
    k_particle          % Wavenumber of particle
  end

  methods (Static)
    function tmatrix = simple(shape, varargin)
      %SIMPLE construct a T-matrix using EBCM for a simple shape.
      %
      % SIMPLE(shape) constructs a new simple T-matrix for the given
      % ott.shapes.Shape object.
      %
      % SIMPLE(name, parameters) constructs a new T-matrix for the
      % shape described by the name and parameters.
      %
      % Supported shape names [parameters]:
      %   'ellipsoid'       Ellipsoid [ a b c]
      %   'cylinder'        z-axis aligned cylinder [ radius height ]
      %   'superellipsoid'  Superellipsoid [ a b c e n ]
      %   'cone-tipped-cylinder'      [ radius height cone_height ]
      %   'cube'            Cube [ width ]
      %   'sphere'          Sphere [ radius ]
      %
      %  TMATRIXEBCM(..., 'Nmax', Nmax) specifies the size of the
      %  T-matrix to use.  If not specified, the size is calculated
      %  from ott.utils.ka2nmax(max_radius*k_medium).
      %
      %  TMATRIXEBCM(..., 'k_medium', k)
      %  or TMATRIXEBCM(..., 'wavelength_medium', wavelength)
      %  or TMATRIXEBCM(..., 'index_medium', index)
      %  specify the wavenumber, wavelength or index in the medium.
      %
      %  TMATRIXEBCM(..., 'wavelength0', wavelength) specifies the
      %  wavelength in the vecuum, required when index_particle or
      %  index_medium are specified.

      p = inputParser;
      p.KeepUnmatched = true;
      p.addOptional('parameters', []);
      p.parse(varargin{:});

      % Get a shape object from the inputs
      if ischar(shape) && ~isempty(p.Results.parameters)
        shape = ott.shapes.Shape.simple(shape, p.Results.parameters);
        varargin = varargin(2:end);
      elseif ~isa(shape, 'ott.shapes.Shape') || ~isempty(p.Results.parameters)
        error('Must input either Shape object or string and parameters');
      end

      % Check the particle is star shaped
      if ~isa(shape, 'ott.shapes.StarShape')
        error('Only star shaped particles supported for now');
      end

      % Check that the particle is rotationally symmetric
      axsym = shape.axialSymmetry();
      if axsym(3) ~= 0
        error('Only axially symetric particles supported for now');
      end

      % Parse optional parameters
      p = inputParser;
      p.KeepUnmatched = true;
      p.addParameter('Nmax', []);
      p.addParameter('k_medium', []);
      p.addParameter('wavelength_medium', []);
      p.addParameter('index_medium', []);
      p.addParameter('wavelength0', []);
      p.parse(varargin{:});

      % Get or estimate Nmax from the inputs
      if isempty(p.Results.Nmax)
        k_medium = ott.Tmatrix.parser_k_medium(p, 2*pi);
        Nmax = ott.utils.ka2nmax(shape.maxRadius * k_medium);
      else
        Nmax = p.Results.Nmax;
      end

      % Get the boudnary points
      [rtp,n,ds] = shape.boundarypoints('Nmax', Nmax);

      % Get the z-axis mirror symmetry and rotational symmetry
      [~, ~, z_rotational_symmetry] = shape.axialSymmetry();
      [~, ~, z_mirror_symmetry] = shape.mirrorSymmetry();

      % Calculate the T-matrix using EBCM
      tmatrix = ott.TmatrixEbcm(rtp, n, ds, varargin{:}, 'Nmax', Nmax, ...
          'rotational_symmetry', z_rotational_symmetry, ...
          'z_mirror_symmetry', z_mirror_symmetry);
    end
  end

  methods
    function tmatrix = TmatrixEbcm(rtp, normals, ds, varargin)
      %TMATRIXEBCM calculates T-matrix using extended boundary condition method
      %
      % TMATRIXEBCM(rtp, normals, ds) uses points at r [ r theta phi ]
      % with normals and steps (ds) to calculate the T-matrix.
      %     r     radius of the point
      %     theta polar angle from +z axis (rad)
      %     phi   azimuthal angle, measured from +x towards +y axes (rad)
      %
      % Note: Only rotationally symetric particles are supported at present.
      %
      %  TMATRIXEBCM(..., 'Nmax', Nmax) specifies the size of the
      %  T-matrix to use.  If not specified, the size is calculated
      %  from ott.utils.ka2nmax(max_radius*k_medium).
      %
      %  TMATRIXEBCM(..., 'k_medium', k)
      %  or TMATRIXEBCM(..., 'wavelength_medium', wavelength)
      %  or TMATRIXEBCM(..., 'index_medium', index)
      %  specify the wavenumber, wavelength or index in the medium.
      %
      %  TMATRIXEBCM(..., 'k_particle', k)
      %  or TMATRIXEBCM(..., 'wavelength_particle', wavelength)
      %  or TMATRIXEBCM(..., 'index_particle', index)
      %  specify the wavenumber, wavelength or index in the particle.
      %
      %  TMATRIXEBCM(..., 'wavelength0', wavelength) specifies the
      %  wavelength in the vecuum, required when index_particle or
      %  index_medium are specified.
      %
      %  TMATRIXEBCM(..., 'rotational_symmetry', sym) if true the particle
      %  is assumed to be rotationally symmetric about the z-axis and
      %  phi must be all the same angle.
      %
      %  TMATRIXEBCM(..., 'z_rotational_symmetry', sym) if true, the particle
      %  is assumed to be mirror symmetric about the xy-plane.

      tmatrix = tmatrix@ott.Tmatrix();

      % Parse inputs
      p = inputParser;
      p.addParameter('Nmax', []);
      p.addParameter('k_medium', []);
      p.addParameter('wavelength_medium', []);
      p.addParameter('index_medium', []);
      p.addParameter('k_particle', []);
      p.addParameter('wavelength_particle', []);
      p.addParameter('index_particle', []);
      p.addParameter('index_relative', []);
      p.addParameter('wavelength0', []);
      p.addParameter('rotational_symmetry', 1);
      p.addParameter('z_mirror_symmetry', false);
      p.parse(varargin{:});

      % Store inputs k_medium and k_particle
      [tmatrix.k_medium, tmatrix.k_particle] = ...
          tmatrix.parser_wavenumber(p, 2*pi);

      % Get or estimate Nmax from the inputs
      if isempty(p.Results.Nmax)
        Nmax = ka2nmax(max(rtp(:, 1)) * tmatrix.k_medium);
      else
        Nmax = p.Results.Nmax;
      end

      % Check that the particle is rotationally symmetric
      if p.Results.rotational_symmetry ~= 0
        % TODO: Add support for non axis symetric particles
        error('Only axis symetric particles supported');
      end

      [~,~,z] = ott.utils.rtp2xyz(rtp);

      mirrorsym = p.Results.z_mirror_symmetry;

      %%%% set up containters
      Y=cell(Nmax,1);
      Ytheta=Y;
      Yphi=Y;

      Nn=zeros(Nmax,1);

      kr=tmatrix.k_particle*rtp(:,1);
      ikr=1./kr;
      kr_=tmatrix.k_medium*rtp(:,1);
      ikr_=1./kr_;

      jkr=cell(Nmax,1);
      jkr_=jkr;
      hkr_=jkr_;

      djkr=jkr;
      djkr_=djkr;
      dhkr_=djkr_;

      Nn=1./sqrt([1:Nmax].*([1:Nmax]+1));

      Nm=repmat(Nn,[Nmax,1]);
      Nm=Nm.'.*Nm;
      
      import ott.utils.*;

      %make all the spharms and bessel functions NOW!!!!
      for ii=1:Nmax

        [Y{ii},Ytheta{ii},Yphi{ii}] = spharm(ii,rtp(:,2),rtp(:,3));

        jkr{ii}=sbesselj(ii,kr);
        jkr_{ii}=sbesselj(ii,kr_);
        hkr_{ii}=sbesselh1(ii,kr_); %%this is conj

        djkr{ii}=sbesselj(ii-1,kr)-ii*jkr{ii}./kr;
        djkr_{ii}=sbesselj(ii-1,kr_)-ii*jkr_{ii}./kr_;
        dhkr_{ii}=sbesselh1(ii-1,kr_)-ii*hkr_{ii}./kr_; %%this is conj

      end

      lengthJs=Nmax^2*(Nmax+2)-sum([1:Nmax-1].*([1:Nmax-1]+1));
      J11=zeros(lengthJs,1);
      J12=J11;
      J21=J11;
      J22=J11;

      RgJ11=J11;
      RgJ12=J11;
      RgJ21=J11;
      RgJ22=J11;

      i_indexes=J11;
      j_indexes=J11;

      Qv=zeros(lengthJs*4,1);
      RgQv=zeros(lengthJs*4,1);

      jcount=0;

      fillnum=(2*Nmax+1);
      rM=repmat(normals(:,1),[1,fillnum]);
      thetaM=repmat(normals(:,2),[1,fillnum]);
      iKr=repmat(ikr,[1,fillnum]);
      iKr_=repmat(ikr_,[1,fillnum]);
      dS=repmat(ds,[1,fillnum]);

      pi2=2*pi;
      %%%% end setup containers
      
      k_medium = tmatrix.k_medium;
      k_particle = tmatrix.k_particle;

      for jj=1:Nmax
        %remember that when phi = 0, conj(Yphi)=-Yphi, conj(Ytheta)=Ytheta.

        for kk=1:Nmax
          p=min(kk,jj);

          indexzk=kk+1+[-p:p];
          indexzj=jj+1+[-p:p];

          els=[1:length(indexzk)];

          jindx=jcount+els;

          i_indexes(jindx)=kk*(kk+1)+[-p:p];
          j_indexes(jindx)=jj*(jj+1)+[-p:p];

          %Calculate the cross products of the spherical harmonics
          YtYp=-Ytheta{jj}(:,indexzj).*Yphi{kk}(:,indexzk);
          YpYt=Yphi{jj}(:,indexzj).*Ytheta{kk}(:,indexzk);

          YYt=Y{jj}(:,indexzj).*Ytheta{kk}(:,indexzk);
          YtY=Ytheta{jj}(:,indexzj).*Y{kk}(:,indexzk);

          YYp=-Y{jj}(:,indexzj).*Yphi{kk}(:,indexzk);
          YpY=Yphi{jj}(:,indexzj).*Y{kk}(:,indexzk);

          YpYp=-Yphi{jj}(:,indexzj).*Yphi{kk}(:,indexzk);
          YtYt=Ytheta{jj}(:,indexzj).*Ytheta{kk}(:,indexzk);

          %calculate the cross products of spherical bessel functions.
          jh_=repmat(jkr{jj}.*(hkr_{kk}),[1,fillnum]);
          jj_=repmat(jkr{jj}.*jkr_{kk},[1,fillnum]);

          jdh_=repmat(jkr{jj}.*(dhkr_{kk}),[1,fillnum]);
          djh_=repmat(djkr{jj}.*(hkr_{kk}),[1,fillnum]);

          jdj_=repmat(jkr{jj}.*djkr_{kk},[1,fillnum]);
          djj_=repmat(djkr{jj}.*jkr_{kk},[1,fillnum]);

          djdh_=repmat(djkr{jj}.*(dhkr_{kk}),[1,fillnum]);
          djdj_=repmat(djkr{jj}.*djkr_{kk},[1,fillnum]);

          % perform the cross product followed by dotting the
          % normal vector and summing over the area elements.

          mfac=(-1).^([-p:p]);
          if ~(mirrorsym&&(rem(jj,2)==rem(kk,2)))
            J11(jindx) = mfac.*(pi2*Nm(jj,kk)* ...
                sum(dS(:,els).*rM(:,els).*jh_(:,els).*(YtYp-YpYt),1));
            J22(jindx) = mfac.*(pi2*Nm(jj,kk)* ...
                sum(dS(:,els).*(rM(:,els).*djdh_(:,els).*(YtYp-YpYt) ...
                -thetaM(:,els).*(jj*(jj+1)*iKr(:,els).* ...
                jdh_(:,els).*YYp - kk*(kk+1)*iKr_(:,els).* ...
                djh_(:,els).*YpY)),1));

            RgJ11(jindx)=mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                rM(:,els).*jj_(:,els).*(YtYp-YpYt),1));
            RgJ22(jindx)=mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                (rM(:,els).*djdj_(:,els).*(YtYp-YpYt) ...
                -thetaM(:,els).*(jj*(jj+1)*iKr(:,els).* ...
                jdj_(:,els).*YYp - kk*(kk+1)*iKr_(:,els).* ...
                djj_(:,els).*YpY)),1));
          end

          if ~(mirrorsym&&(rem(jj,2)~=rem(kk,2)))
            J12(jindx) = mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                (rM(:,els).*jdh_(:,els).*(YpYp+YtYt) ...
                -kk*(kk+1)*iKr_(:,els).*thetaM(:,els).* ...
                jh_(:,els).*YtY),1));
            J21(jindx) = mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                (-rM(:,els).*djh_(:,els).*(YtYt+YpYp) ...
                +jj*(jj+1)*iKr(:,els).*thetaM(:,els).*jh_(:,els).*YYt),1));

            RgJ12(jindx)=mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                (rM(:,els).*jdj_(:,els).*(YpYp+YtYt) ...
                -kk*(kk+1)*iKr_(:,els).*thetaM(:,els).*jj_(:,els).*YtY),1));
            RgJ21(jindx)=mfac.*(pi2*Nm(jj,kk)*sum(dS(:,els).* ...
                (-rM(:,els).*djj_(:,els).*(YtYt+YpYp) ...
                +jj*(jj+1)*iKr(:,els).*thetaM(:,els).*jj_(:,els).*YYt),1));
          end
          jcount=jcount+length(indexzj);

        end
      end

      %Set up the Q and RgQ for sparse input:
      Qv(1:lengthJs)=1i*k_medium*(k_particle*J21+k_medium*J12);
      Qv(lengthJs+1:lengthJs*2)=1i*k_medium*(k_particle*J11+k_medium*J22);
      Qv(2*lengthJs+1:lengthJs*3)=1i*k_medium*(k_particle*J22+k_medium*J11);
      Qv(3*lengthJs+1:lengthJs*4)=1i*k_medium*(k_particle*J12+k_medium*J21);

      RgQv(1:lengthJs)=1i*k_medium*(k_particle*RgJ21+k_medium*RgJ12);
      RgQv(lengthJs+1:lengthJs*2)=1i*k_medium* ...
          (k_particle*RgJ11+k_medium*RgJ22);
      RgQv(2*lengthJs+1:lengthJs*3)=1i*k_medium* ...
          (k_particle*RgJ22+k_medium*RgJ11);
      RgQv(3*lengthJs+1:lengthJs*4)=1i*k_medium* ...
          (k_particle*RgJ12+k_medium*RgJ21);

      %Convert the vectors of Q and RgQ into sparse vector form:
      i_s=[i_indexes;i_indexes;i_indexes+Nmax*(Nmax+2); ...
          i_indexes+Nmax*(Nmax+2)];
      j_s=[j_indexes;j_indexes+Nmax*(Nmax+2);j_indexes; ...
          j_indexes+Nmax*(Nmax+2)];
      Q=sparse(i_s,j_s,Qv,2*Nmax*(Nmax+2),2*Nmax*(Nmax+2));
      RgQ=sparse(i_s,j_s,RgQv,2*Nmax*(Nmax+2),2*Nmax*(Nmax+2));

      %solve the T-matrix:
      tmatrix.data=-(RgQ/Q);

      % Store the type of T-matrix
      tmatrix.type = 'scattered';
    end
  end
end
