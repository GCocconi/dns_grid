!!!.....................................................................
!!!........................FFTW3 MOD....................................
!!!.....................................................................
MODULE time_advancement_mod
USE parameters_mod
USE variables_mod
USE MPI_mod
! USE fft_mod
USE grid_forcing_mod
USE stats_and_probes_mod
! USE hit_forcings_mod
#INCLUDE 'fpp_macros.h'
implicit none

REAL(KIND=rk),DIMENSION(4,3:4)            :: ark,brk
INTEGER(KIND=ik),DIMENSION(0:3)           :: i_rk
INTEGER(KIND=ik)                          :: n_k

contains

!!!. . . . . . . . . . . . . .CROSS. . . . . . . . . . . . . . . . . . .
FUNCTION cross(a,b)
!compute cross product between complex numbers
 implicit none
 COMPLEX(KIND=rk), DIMENSION(3) :: cross
 COMPLEX(KIND=rk), DIMENSION(3), INTENT(IN) :: a, b
 cross(1) = a(2) * b(3) - a(3) * b(2)
 cross(2) = a(3) * b(1) - a(1) * b(3)
 cross(3) = a(1) * b(2) - a(2) * b(1)
END FUNCTION cross

!!!. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
SUBROUTINE TA_rk_initialize
 !! Sets the Runge-Kutta coefficients for the time integration scheme
 !! brk coefficients are permutated by one position in order to match
 !! the correct time level

      !!Runge-Kutta 3rd order
      ark(1,3)=8._rk/15._rk
      ark(2,3)=5._rk/12._rk
      ark(3,3)=3._rk/4._rk
      brk(1,3)=0._rk
      brk(2,3)=-17._rk/60._rk
      brk(3,3)=-5._rk/12._rk
      !!Runge-Kutta 4th order
      ark(1,4)=8._rk/17._rk
      ark(2,4)=17._rk/60._rk
      ark(3,4)=5._rk/12._rk
      ark(4,4)=3._rk/4._rk
      brk(1,4)=0._rk
      brk(2,4)=-15._rk/68._rk
      brk(3,4)=-17._rk/60._rk
      brk(4,4)=-5._rk/12._rk
END SUBROUTINE TA_rk_initialize

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
SUBROUTINE TA_partial_right_hand_side
!!TODO: trasformare in una funzione che prende variabili di qualsiasi shape
implicit none
COMPLEX(KIND=rk)                             :: k_quad
REAL(KIND=rk)                                :: pnrk,qnrk
INTEGER(KIND=ik)                             :: zz,yy,xx,jj,kk

 pnrk=2_rk*Re/(dt*ark(n_k,rk_steps)+dt*brk(n_k,rk_steps))

 qnrk=dt*brk(n_k,rk_steps)*pnrk

 ZL10: DO zz=1,Csize(3)
 YL10: DO yy=1,Csize(2)
 XL10: DO xx=1,Csize(1)-1
       k_quad=(kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2)
       puu_C(xx,yy,zz,:)=(pnrk+k_quad)*uu_C(xx,yy,zz,:)+qnrk*hh_C(xx,yy,zz,:)
 ENDDO XL10
 ENDDO YL10
 ENDDO ZL10

 MASTER PRINT *,'prhs',puu_C(7,12,12,1)
 MASTER PRINT *,'prhs',uu_C(7,12,12,1)
 xx=7
 yy=12
 zz=12
 jj=day(yy)
 kk=daz(zz)
 k_quad=(kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2)
 MASTER PRINT *,pnrk,k_quad,ark(n_k,rk_steps),brk(n_k,rk_steps)
 MASTER PRINT *,pnrk+k_quad,qnrk*hh_C(xx,yy,zz,1)
END SUBROUTINE TA_partial_right_hand_side

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
SUBROUTINE TA_nonlinear
 !! Compute non-linear terms in the phisical space and transform them back
 !! in the Fourier space
 !! Enforce zero-divergence on the trasnformed non-linear terms
 implicit none
 INTEGER(KIND=ik)               :: xx,yy,zz
 INTEGER(KIND=ik)               :: jj,kk
 COMPLEX(KIND=rk)               :: k_quad
 COMPLEX(KIND=rk)               :: ac1,ac2,ac3,div
 REAL(KIND=rk)                  :: norm,ff1,ff2,ff3
 REAL(KIND=rk)                  :: ff1_glob,ff2_glob,ff3_glob
 REAL(KIND=rk)                  :: a1,a2,a3,b1,b2,b3
 REAL(KIND=rk)                  :: xf_min,xf_max,delta_xf
 REAL(KIND=rk)                  :: coeff,amp_x


 norm=1_rk/REAL(nxp*nyp*nzp,KIND=rk)

 !! Sets x-bounds of the forced region
 delta_xf=0.5_rk*xl*thick
 xf_min=(-delta_xf + xl/2_rk) * REAL(nxp,KIND=rk)/ xl  !left bound of the forced region
 xf_max=(+delta_xf + xl/2_rk) * REAL(nxp,KIND=rk)/ xl  !right bound of the force region
 ! aa=1.5*pi
 ! coeff=1_rk/(sigma*SQRT(2_rk*pi))


 !! Computes vorticity in the fourier space and puts it in hu hv hw
 ZL10 : DO zz=1,Csize(3)
 YL10 :    DO yy=1,Csize(2)
 XL10 :       DO xx=1,Csize(1)-1
             jj=day(yy)
             kk=daz(zz)
             hh_C(xx,yy,zz,:)=cross((/ kx(xc_loc(xx)), ky(yc_loc(yy)), kz(zc_loc(zz)) /),&
             (/ uu_C(xx,yy,zz,1), uu_C(xx,yy,zz,2), uu_C(xx,yy,zz,3) /))
              ENDDO XL10
          ENDDO YL10
       ENDDO ZL10

    ! CALL B_FFT(hh_C,hh)
    ! CALL B_FFT(uu_C,uu)
     MASTER PRINT *,'fft',uu_C(7,12,12,1)
     MASTER PRINT *,'fft',hh_C(7,12,12,1)

    CALL_BARRIER

    CALL p3dfft_btran_c2r_many (uu_C,Csize(1)*Csize(2)*Csize(3),uu, &
                Rsize(1)*Rsize(2)*Rsize(3),3,'tff')
    CALL p3dfft_btran_c2r_many (hh_C,Csize(1)*Csize(2)*Csize(3),hh, &
                Rsize(1)*Rsize(2)*Rsize(3),3,'tff')

    CALL_BARRIER
    MASTER PRINT *,'u ta   ::',uu(4,4,4,1)
    MASTER PRINT *,'hh ta  ::',hh(4,4,4,1)

    CALL STATS_average_energy(stats_time)
      !   DO zz=1,nzp
      !    DO yy=1,nxp
      !         if (fu(yy,zz)/=fu(yy,zz)) print *,yy,zz,1
      !         if (fv(yy,zz)/=fv(yy,zz)) print *,yy,zz,2
      !         if (fw(yy,zz)/=fw(yy,zz)) print *,yy,zz,3
      !       ENDDO
      !       ENDDO

!! Compute non-linear term in the phisical space
!! If within the forced region adds the forcing term multiplied by
!! a gaussian distribution function of xx
         ff1=0.;ff2=0.;ff3=0.
  ZL20 : DO zz=1,Rsize(3)
  YL20 : DO yy=1,Rsize(2)
  XL20 : DO xx=1,Rsize(1)
         a1=uu(xx,yy,zz,1)
         a2=uu(xx,yy,zz,2)
         a3=uu(xx,yy,zz,3)

         b1=hh(xx,yy,zz,1)
         b2=hh(xx,yy,zz,2)
         b3=hh(xx,yy,zz,3)

         hh(xx,yy,zz,1)=a2*b3-a3*b2
         hh(xx,yy,zz,2)=a3*b1-a1*b3
         hh(xx,yy,zz,3)=a1*b2-a2*b1

        !  hh(xx,yy,zz,:)=cross((/ uu(xx,yy,zz,1), uu(xx,yy,zz,2), uu(xx,yy,zz,3) /),&
        !  (/ hh(xx,yy,zz,1), hh(xx,yy,zz,2), hh(xx,yy,zz,3) /))

        !! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
        !! Forcing input in the physical space for the grid forcing
         IF (REAL(xr_loc(xx),KIND=rk) > xf_min-nxp/8 .AND. REAL(xr_loc(xx),KIND=rk) < xf_max +nxp/8) THEN

      !    amp_x=coeff*EXP(- (REAL(xr_loc(xx)-nxp/2,KIND=rk)*xl/REAL(nxp,KIND=rk) )**2/sigma)
         amp_x=0.5*(1 + TANH(aa*(delta_xf-abs(REAL(nxp/2-xr_loc(xx),KIND=rk))*xl/REAL(nxp,KIND=rk) )))

         hh(xx,yy,zz,1)=hh(xx,yy,zz,1) + fu(yr_loc(yy),zr_loc(zz))*amp_x
         hh(xx,yy,zz,2)=hh(xx,yy,zz,2) + fv(yr_loc(yy),zr_loc(zz))*amp_x
         hh(xx,yy,zz,3)=hh(xx,yy,zz,3) + fw(yr_loc(yy),zr_loc(zz))*amp_x
         ff1=ff1+(fu(yr_loc(yy),zr_loc(zz))*amp_x)**2/REAL(nxp*nyp*nzp,KIND=rk)
         ff2=ff2+(fv(yr_loc(yy),zr_loc(zz))*amp_x)**2/REAL(nxp*nyp*nzp,KIND=rk)
         ff3=ff3+(fw(yr_loc(yy),zr_loc(zz))*amp_x)**2/REAL(nxp*nyp*nzp,KIND=rk)
         ENDIF
         !! - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  ENDDO XL20
  ENDDO YL20
  ENDDO ZL20


      CALL MPI_REDUCE(ff1, ff1_glob, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, mpi_comm_world,ierr)
      CALL MPI_REDUCE(ff2, ff2_glob, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, mpi_comm_world,ierr)
      CALL MPI_REDUCE(ff3, ff3_glob, 1, MPI_DOUBLE_PRECISION, MPI_SUM, 0, mpi_comm_world,ierr)
         print *,'ff',ff1_glob,ff2_glob,ff3_glob,hh(nxp/2,nyp/2,nzp/2,1)

   CALL STATS_compute_CFL

   ! CALL HIT_linear_forcing
   ! if (proc_id==0) then
   !       if (it==3) then
   !              do xx=1,nxp
   !              write(18,*) uu(xx,1,1,1),uu(xx,1,1,2),uu(xx,1,1,3)
   !              enddo
   !              CALL_BARRIER
   !                stop
   !        endif
   ! endif
   ! CALL F_FFT(hh,hh_C)
   ! CALL F_FFT(uu,uu_C)
   CALL_BARRIER
   CALL p3dfft_ftran_r2c_many (uu,Rsize(1)*Rsize(2)*Rsize(3),uu_C, &
                           Csize(1)*Csize(2)*Csize(3),3,'fft')
   CALL p3dfft_ftran_r2c_many (hh,Rsize(1)*Rsize(2)*Rsize(3),hh_C, &
                           Csize(1)*Csize(2)*Csize(3),3,'fft')

    uu_C=uu_C/REAL(nxp*nyp*nzp,KIND=rk)
    hh_C=hh_C/REAL(nxp*nyp*nzp,KIND=rk)
    ! if (it==3) then
    !       write(18,*) real(uu_C(:,1,1,:))
    !       stop
    ! endif
!! FIXME it works only for 1D slicing
!!!=============================================================================
! if (yc_loc(1)==1) then
! hh_C(5,1,1,1)=hh_C(5,1,1,1)+CMPLX(0_rk,0_rk)
! hh_C(5,1,1,2)=hh_C(5,1,1,2)+CMPLX(0_rk,-0.5_rk)
! hh_C(5,1,1,3)=hh_C(5,1,1,3)+CMPLX(0.5_rk,0_rk)
! endif
!
! if (yc_loc(1)==1) then
! hh_C(1,5,1,1)=hh_C(1,5,1,1)+CMPLX(0.5_rk,0_rk)
! hh_C(1,5,1,2)=hh_C(1,5,1,2)+CMPLX(0_rk,0_rk)
! hh_C(1,5,1,3)=hh_C(1,5,1,3)+CMPLX(0_rk,-0.5_rk)
! endif
!
! if (yc_loc(Csize(2)-5+2)==ny-5+2) then
! hh_C(1,Csize(2)-5+2,1,1)=hh_C(1,Csize(2)-5+2,1,1)+CMPLX(0.5_rk,0_rk)
! hh_C(1,Csize(2)-5+2,1,2)=hh_C(1,Csize(2)-5+2,1,2)+CMPLX(0_rk,0_rk)
! hh_C(1,Csize(2)-5+2,1,3)=hh_C(1,Csize(2)-5+2,1,3)+CMPLX(0_rk,0.5_rk)
! endif
!
! if (yc_loc(1)==1) then
! if (zc_loc(1)==1) then
! hh_C(1,1,5,1)=hh_C(1,1,5,1)+CMPLX(0_rk,-0.5_rk)
! hh_C(1,1,5,2)=hh_C(1,1,5,2)+CMPLX(0.5_rk,0_rk)
! hh_C(1,1,5,3)=hh_C(1,1,5,3)+CMPLX(0_rk,0_rk)
! endif
!
! if (zc_loc(Csize(3)-5+2)==nz-5+2) then
!
! hh_C(1,1,Csize(3)-5+2,1)=hh_C(1,1,Csize(3)-5+2,1)+CMPLX(0_rk,0.5_rk)
! hh_C(1,1,Csize(3)-5+2,2)=hh_C(1,1,Csize(3)-5+2,2)+CMPLX(0.5_rk,0_rk)
! hh_C(1,1,Csize(3)-5+2,3)=hh_C(1,1,Csize(3)-5+2,3)+CMPLX(0_rk,0_rk)
! endif
! endif
!!!=============================================================================

! hh_C(4,4,4,2)=hh_C(4,4,4,2)+CMPLX(1_rk,1_rk)
! hh_C(4,4,4,3)=hh_C(4,4,4,3)+CMPLX(1_rk,1_rk)

! print *,'forc',hh_C(4,4,4,3)
 ZL30 : DO zz=1,Csize(3)
 YL30 :    DO yy=1,Csize(2)
            xx=1
            jj=day(yy)
            kk=daz(zz)
              IF(yc_loc(yy)==1 .AND. zc_loc(zz)==1) THEN
                hh_C(xx,yy,zz,1)=CMPLX(0._rk,0._rk)
                hh_C(xx,yy,zz,2)=CMPLX(0._rk,0._rk)
                hh_C(xx,yy,zz,3)=CMPLX(0._rk,0._rk)
              ELSE
                ac1=hh_C(xx,yy,zz,1)
                ac2=hh_C(xx,yy,zz,2)
                ac3=hh_C(xx,yy,zz,3)

                k_quad=kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2
                k_quad=1._rk/k_quad
            !     k_quad=1./max(1.0E-10,abs(k_quad))

                div=kx(xc_loc(xx))*hh_C(xx,yy,zz,1)&
                   +ky(yc_loc(yy))*hh_C(xx,yy,zz,2)&
                   +kz(zc_loc(zz))*hh_C(xx,yy,zz,3)


                hh_C(xx,yy,zz,1)=ac1-div*kx(xc_loc(xx))*k_quad
                hh_C(xx,yy,zz,2)=ac2-div*ky(yc_loc(yy))*k_quad
                hh_C(xx,yy,zz,3)=ac3-div*kz(zc_loc(zz))*k_quad
              ENDIF

 XL31 :       DO xx=2,Csize(1)-1
 ! XL31 :       DO xx=1,nx/2

              ac1=hh_C(xx,yy,zz,1)
              ac2=hh_C(xx,yy,zz,2)
              ac3=hh_C(xx,yy,zz,3)

               k_quad=kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2
               k_quad=1._rk/k_quad
            !    k_quad=1./max(1.0E-10,abs(k_quad))

               div=kx(xc_loc(xx))*hh_C(xx,yy,zz,1)&
                  +ky(yc_loc(yy))*hh_C(xx,yy,zz,2)&
                  +kz(zc_loc(zz))*hh_C(xx,yy,zz,3)

                  hh_C(xx,yy,zz,1)=ac1-div*kx(xc_loc(xx))*k_quad
                  hh_C(xx,yy,zz,2)=ac2-div*ky(yc_loc(yy))*k_quad
                  hh_C(xx,yy,zz,3)=ac3-div*kz(zc_loc(zz))*k_quad


 ENDDO XL31
 ENDDO YL30
 ENDDO ZL30
      ! CALL TA_divfree(hh_C)
      ! CALL HIT_alvelius_forcing
 MASTER PRINT *,'prima di lin',hh_C(7,12,12,1)
END SUBROUTINE TA_nonlinear

!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
!! . . . . . . . . . . . . . . . . LINEAR . . . . . . . . . . . . . . . . . . .
SUBROUTINE TA_linear
 implicit none
 INTEGER(KIND=ik)               :: zz,yy,xx,jj,kk
 COMPLEX(KIND=rk)               :: k_quad
 REAL(KIND=rk)                  :: den,pnrk,qnrk

 ! n_k=i_rk(mod(it,rk_steps))

 pnrk=2_rk*Re/(dt*ark(n_k,rk_steps)+dt*brk(n_k,rk_steps))

 qnrk=dt*ark(n_k,rk_steps)*pnrk

 ZL10 : DO zz=1,Csize(3)
 YL10 : DO yy=1,Csize(2)
 XL10 : DO xx=1,Csize(1)-1
               jj=day(yy)
               kk=daz(zz)
               k_quad=kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2
               den=1./(pnrk-k_quad)
               uu_C(xx,yy,zz,:)=(puu_C(xx,yy,zz,:)+qnrk*hh_C(xx,yy,zz,:))*den

 ENDDO XL10
 ENDDO YL10
 ENDDO ZL10
  MASTER PRINT *,'linear',puu_C(7,12,12,1)
 MASTER PRINT *,'linear',uu_C(7,12,12,1)
END SUBROUTINE TA_linear
!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
SUBROUTINE TA_divfree(vv_C)

IMPLICIT NONE

INTEGER(KIND=IK)                                   ::xx,yy,zz,jj,kk
COMPLEX(KIND=rk)                                   :: k_quad
COMPLEX(KIND=rk)                                   :: ac1,ac2,ac3,div
COMPLEX(KIND=rk),DIMENSION(:,:,:,:), INTENT(INOUT) :: vv_C

ZL30 : DO zz=1,Csize(3)
YL30 :    DO yy=1,Csize(2)
           xx=1
           jj=day(yy)
           kk=daz(zz)
            !  IF(jj==1 .AND. zz==1) THEN
            !    vv_C(xx,jj,zz,1)=CMPLX(0._rk,0._rk)
            !    vv_C(xx,jj,zz,2)=CMPLX(0._rk,0._rk)
            !    vv_C(xx,jj,zz,3)=CMPLX(0._rk,0._rk)
            !  ELSE
               ac1=vv_C(xx,yy,zz,1)
               ac2=vv_C(xx,yy,zz,2)
               ac3=vv_C(xx,yy,zz,3)

               k_quad=kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2
               k_quad=1._rk/k_quad
           !     k_quad=1./max(1.0E-10,abs(k_quad))

               div=kx(xc_loc(xx))*vv_C(xx,yy,zz,1)&
                  +ky(yc_loc(yy))*vv_C(xx,yy,zz,2)&
                  +kz(zc_loc(zz))*vv_C(xx,yy,zz,3)
             IF(yy==1 .AND. zz==1) THEN
                   k_quad=CMPLX(0._rk,0._rk)
             ENDIF

               vv_C(xx,yy,zz,1)=ac1-div*kx(xc_loc(xx))*k_quad
               vv_C(xx,yy,zz,2)=ac2-div*ky(yc_loc(yy))*k_quad
               vv_C(xx,yy,zz,3)=ac3-div*kz(zc_loc(zz))*k_quad
            !  ENDIF

XL31 :       DO xx=2,Csize(1)-1
! XL31 :       DO xx=1,nx/2

             ac1=vv_C(xx,yy,zz,1)
             ac2=vv_C(xx,yy,zz,2)
             ac3=vv_C(xx,yy,zz,3)

              k_quad=kx(xc_loc(xx))**2+ky(yc_loc(yy))**2+kz(zc_loc(zz))**2
              k_quad=1._rk/k_quad
           !    k_quad=1./max(1.0E-10,abs(k_quad))

              div=kx(xc_loc(xx))*vv_C(xx,yy,zz,1)&
                 +ky(yc_loc(yy))*vv_C(xx,yy,zz,2)&
                 +kz(zc_loc(zz))*vv_C(xx,yy,zz,3)

                 vv_C(xx,yy,zz,1)=ac1-div*kx(xc_loc(xx))*k_quad
                 vv_C(xx,yy,zz,2)=ac2-div*ky(yc_loc(yy))*k_quad
                 vv_C(xx,yy,zz,3)=ac3-div*kz(zc_loc(zz))*k_quad


ENDDO XL31
ENDDO YL30
ENDDO ZL30
END SUBROUTINE TA_divfree


!! . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

END MODULE time_advancement_mod

!!!.....................................................................
!!!.....................................................................
!!!.....................................................................
!!TODO routines per statistiche: energia,dissipazione,potenza
