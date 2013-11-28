module atomic_functions
use math_functions
use vars
implicit none
contains
	
!-----------------------------------------------------------------
! Return the profiles weighted by the strength of the components for a given frequency
! It returns zeeman_profile(q,n_depths) with
!  q=1  Mlow=Mup-1  (sigma blue)
!  q=2  Mlow=Mup    (sigma pi)
!  q=3  Mlow=Mup+1  (sigma red)
!-----------------------------------------------------------------	
	subroutine zeeman_profile(Stokes_Syn,model,linea,zeeman_voigt,zeeman_faraday)
	type(stokes_type) :: Stokes_Syn
	type(modelo_type) :: model
	type(line_type) :: linea
	real(kind=8) :: zeeman_voigt(:,:), zeeman_faraday(:,:)
	integer :: n, nlow, nup, iup, ilow, i_pi, i_blue, i_red, cual
	real(kind=8) :: Mup, Mlow, strength, va, vb, splitting
	real(kind=8), allocatable :: profile(:,:), v(:)
	
		n = size(zeeman_voigt(1,:))		
		
		allocate(profile(2,n))
		allocate(v(n))
		
		nup = 2*linea%Jup+1
		nlow = 2*linea%Jlow+1
		
		zeeman_voigt = 0.d0
		zeeman_faraday = 0.d0
		
		i_red = 0
		i_pi = 0
		i_blue = 0
		
		v = (Stokes_Syn%lambda-linea%wave0) / model%doppler
		va = linea%wave0 * model%vmac / (PC*model%doppler)
		vb = linea%wave0**2 * model%Bfield * 4.6686d-13 / model%doppler
				
		do iup = 1, nup
			Mup = linea%Jup + 1 - iup  ! Mup=J...-J
			do ilow = 1, 3
				Mlow = Mup-2+ilow			! Mlow=Mup-1,Mup,Mup+1 (the allowed transitions)
				if (abs(Mlow) <= linea%Jlow) then
					
					if (ilow == 1) then
						i_blue = i_blue + 1
						cual = i_blue
					endif
					if (ilow == 2) then
						i_pi = i_pi + 1
						cual = i_pi
					endif
					if (ilow == 3) then
						i_red = i_red + 1
						cual = i_red
					endif
					
					strength = strength_zeeman(linea%Jup,linea%Jlow,Mup,Mlow)
					splitting = linea%gup*Mup - linea%glow*Mlow

					profile = fvoigt_zeeman(model%damping,v-va+vb*splitting)
					zeeman_voigt(ilow,:) = zeeman_voigt(ilow,:) + strength * profile(1,:) / sqrt(PI)
					zeeman_faraday(ilow,:) = zeeman_faraday(ilow,:) + strength * profile(2,:) / sqrt(PI)		
				endif
			enddo
		enddo	
		
		deallocate(profile)
		deallocate(v)
		
	end subroutine zeeman_profile
		
!-----------------------------------------------------------------
! Return the seven independent elements of the absorption matrix
! Remember that, zeeman_voigt(q,:) and zeeman_faraday(q,:) have
!  q=1  Mlow=Mup-1  (sigma blue)
!  q=2  Mlow=Mup    (sigma pi)
!  q=3  Mlow=Mup+1  (sigma red)
!-----------------------------------------------------------------	
	subroutine zeeman_opacity(model,line,zeeman_voigt,zeeman_faraday,ki,kq,ku,kv,fq,fu,fv)
	type(modelo_type) :: model
	integer :: line
	real(kind=8) :: zeeman_voigt(:,:), zeeman_faraday(:,:)
	real(kind=8) :: ki(:), kq(:), ku(:), kv(:), fq(:), fu(:), fv(:)
	real(kind=8) :: sin_theta, cos_theta, sin_2chi, cos_2chi

		sin_theta = sin(model%theta * PI / 180.d0)
		cos_theta = cos(model%theta * PI / 180.d0)
		
		sin_2chi = sin(2.d0 * model%chi * PI / 180.d0)
		cos_2chi = cos(2.d0 * model%chi * PI / 180.d0)
		
! Classical absorption coefficients
		ki = 0.5d0 * (zeeman_voigt(2,:)*sin_theta**2 + 0.5d0*(zeeman_voigt(1,:)+zeeman_voigt(3,:))*(1.d0+cos_theta**2))  ! eta_I
		kq = 0.5d0 * (zeeman_voigt(2,:) - 0.5d0*(zeeman_voigt(1,:)+zeeman_voigt(3,:))) * sin_theta**2*cos_2chi  ! eta_Q
		ku = 0.5d0 * (zeeman_voigt(2,:) - 0.5d0*(zeeman_voigt(1,:)+zeeman_voigt(3,:))) * sin_theta**2*sin_2chi  ! eta_U
		kv = 0.5d0 * (zeeman_voigt(3,:)-zeeman_voigt(1,:)) * cos_theta  ! eta_V
		
! Magneto-optical coefficients		
		fq = 0.5d0 * (zeeman_faraday(2,:) - 0.5d0*(zeeman_faraday(1,:)+zeeman_faraday(3,:))) * sin_theta**2*cos_2chi  ! rho_Q
		fu = 0.5d0 * (zeeman_faraday(2,:) - 0.5d0*(zeeman_faraday(1,:)+zeeman_faraday(3,:))) * sin_theta**2*sin_2chi  ! rho_U
		fv = 0.5d0 * (zeeman_faraday(3,:)-zeeman_faraday(1,:)) * cos_theta  ! rho_V
		
		ki = model%kl(line) * ki
		kq = model%kl(line) * kq
		ku = model%kl(line) * ku
		kv = model%kl(line) * kv
		fq = model%kl(line) * fq
		fu = model%kl(line) * fu
		fv = model%kl(line) * fv
				
	end subroutine zeeman_opacity	
	
	
!-----------------------------------------------------------------
! Add the atomic opacity to the opacity including the effect of a magnetic field
!-----------------------------------------------------------------	
	subroutine synthesize(model,linea,Stokes_Syn)
	type(modelo_type) :: model(:)
	type(stokes_type) :: Stokes_Syn
	type(line_type) :: linea(:)
	integer :: i, j, k, n, n_lineas
	real(kind=8), allocatable :: ki(:), kq(:), ku(:), kv(:), fq(:), fu(:), fv(:), stokes(:,:), delta(:)
	real(kind=8), allocatable :: ki_partial(:), kq_partial(:), ku_partial(:), kv_partial(:)
	real(kind=8), allocatable :: fq_partial(:), fu_partial(:), fv_partial(:)
	real(kind=8) :: factor1 ,factor2, lmax, lmin, lstep
	character(len=1) :: str
		
		n_lineas = size(linea)
							
! Calculate wavelength axis. Unique for all the lines		
		lmax = 0
		lmin = 1.d20
		lstep = 1.d20
		do i = 1, n_lineas
			lmax = max(lmax,linea(i)%lambda_end)
			lmin = min(lmin,linea(i)%lambda_init)
			lstep = min(lstep,linea(i)%lambda_step)
		enddo
				
		n = (lmax-lmin) / lstep		
		Stokes_Syn%nlambda = n
						
		if (.not.associated(Stokes_Syn%lambda)) allocate(Stokes_Syn%lambda(n))
		if (.not.associated(Stokes_Syn%stokes)) allocate(Stokes_Syn%stokes(4,n))
		
		Stokes_Syn%stokes = 0.d0
		
		allocate(zeeman_voigt(3,n))
		allocate(zeeman_faraday(3,n))

		allocate(ki_partial(n))
		allocate(kq_partial(n))
		allocate(ku_partial(n))
		allocate(kv_partial(n))
		allocate(fq_partial(n))
		allocate(fu_partial(n))
		allocate(fv_partial(n))
		
		allocate(ki(n))
		allocate(kq(n))
		allocate(ku(n))
		allocate(kv(n))
		allocate(fq(n))
		allocate(fu(n))
		allocate(fv(n))
		
		allocate(delta(n))
		allocate(stokes(4,n))				

		do k = 1, n
			Stokes_Syn%lambda(k) = lmin + lstep * (k-1)			
		enddo
						
		do j = 1, number_of_components
			
! If it is a stray-light contamination
			if (model(j)%stray_light_component) then				
				if (model(j)%stray_light_nlambda /= Stokes_Syn%nlambda) then
					print *, 'Not consistent number of wavelengths in stray light profile...'
					stop
				endif
				Stokes_Syn%stokes = Stokes_Syn%stokes + &
					model(j)%filling_factor * model(j)%straylight
				
			else
! Or a standard model
				factor1 = 1.d0 / (1.d0 + model(j)%beta*model(j)%mu)
				factor2 = -model(j)%beta*model(j)%mu * factor1
				
				ki = 0.d0
				kq = 0.d0
				ku = 0.d0
				kv = 0.d0
				fq = 0.d0
				fu = 0.d0
				fv = 0.d0
			
				do i = 1, n_lineas				
					call zeeman_profile(Stokes_Syn,model(j),linea(i),zeeman_voigt,zeeman_faraday)
					
					call zeeman_opacity(model(j),i,zeeman_voigt,zeeman_faraday,ki_partial,kq_partial,&
						ku_partial,kv_partial,fq_partial,fu_partial,fv_partial)
									
					ki = ki + ki_partial
					kq = kq + kq_partial
					ku = ku + ku_partial
					kv = kv + kv_partial
					fq = fq + fq_partial
					fu = fu + fu_partial
					fv = fv + fv_partial
				enddo
					
				delta = (1.d0+ki)**4 + (1.d0+ki)**2 * (fq**2+fu**2+fv**2-kq**2-ku**2-kv**2) - &
					(kq*fq+ku*fu+kv*fv)**2
		
				stokes(1,:) = factor1 * (1.d0+model(j)%beta*model(j)%mu*(1.d0+ki) / delta * &
					((1.d0+ki)**2 + fq**2 + fu**2 + fv**2))
				stokes(2,:) = factor2 / delta * ((1.d0+ki)**2*kq - (1.d0+ki)*(ku*fv-kv*fu) + &
					fq*(kq*fq+ku*fu+kv*fv))
				stokes(3,:) = factor2 / delta * ((1.d0+ki)**2*ku - (1.d0+ki)*(kv*fq-kq*fv) + &
					fu*(kq*fq+ku*fu+kv*fv))
				stokes(4,:) = factor2 / delta * ((1.d0+ki)**2*kv - (1.d0+ki)*(kq*fu-ku*fq) + &
					fv*(kq*fq+ku*fu+kv*fv))
			
				Stokes_Syn%stokes = Stokes_Syn%stokes + model(j)%filling_factor * stokes
			endif
			
		enddo

		deallocate(zeeman_voigt)
		deallocate(zeeman_faraday)
		deallocate(ki)
		deallocate(kq)
		deallocate(ku)
		deallocate(kv)
		deallocate(fq)
		deallocate(fu)
		deallocate(fv)
		
		deallocate(ki_partial)
		deallocate(kq_partial)
		deallocate(ku_partial)
		deallocate(kv_partial)
		deallocate(fq_partial)
		deallocate(fu_partial)
		deallocate(fv_partial)
		
		deallocate(stokes)
		deallocate(delta)

	end subroutine synthesize
		
end module atomic_functions
