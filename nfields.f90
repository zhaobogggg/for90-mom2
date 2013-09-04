! MODULE: nfields
! AUTHOR: Jouni Makitalo
! DESCRIPTION:
! Routines to compute the scattered fields in the vicinity
! of scatterers.
MODULE nfields
  USE srcint

  IMPLICIT NONE

  TYPE nfield_plane
     REAL (KIND=dp), DIMENSION(3) :: origin, v1, v2
     REAL (KIND=dp) :: d1, d2
     INTEGER :: n1, n2
  END TYPE nfield_plane

CONTAINS
  ! If multidomain description is used, domain is the domain index referencing
  ! b%domains. Otherwise domain==1 corresponds to exterior and domain==2 to interior
  ! domain.
  SUBROUTINE scat_fields(mesh, ga, x, nedgestot, omega, ri, prd, r, e, h)
    TYPE(mesh_container), INTENT(IN) :: mesh
    COMPLEX (KIND=dp), INTENT(IN) :: ri
    REAL (KIND=dp), INTENT(IN) :: omega
    INTEGER, INTENT(IN) :: nedgestot
    TYPE(group_action), DIMENSION(:), INTENT(IN) :: ga
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), DIMENSION(:,:), INTENT(IN) :: x
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r

    COMPLEX (KIND=dp), DIMENSION(3), INTENT(INOUT) :: e, h
    COMPLEX (KIND=dp), DIMENSION(3) :: e2, h2
    INTEGER :: nf

    e(:) = 0.0_dp
    h(:) = 0.0_dp

    DO nf=1,SIZE(ga)
       CALL scat_fields_frag(mesh, ga, nf, x(:,nf), nedgestot, omega, ri, prd, r, e, h)

       e = e + e2
       h = h + h2
    END DO
  END SUBROUTINE scat_fields

  SUBROUTINE scat_fields_frag(mesh, ga, nf, x, nedgestot, omega, ri, prd, r, e, h)
    TYPE(mesh_container), INTENT(IN) :: mesh
    COMPLEX (KIND=dp), INTENT(IN) :: ri
    REAL (KIND=dp), INTENT(IN) :: omega
    TYPE(group_action), DIMENSION(:), INTENT(IN) :: ga
    INTEGER, INTENT(IN) :: nf, nedgestot
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), DIMENSION(:), INTENT(IN) :: x
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r

    COMPLEX (KIND=dp), DIMENSION(3), INTENT(INOUT) :: e, h

    INTEGER :: n, q, index, ns
    COMPLEX (KIND=dp) :: c1, c2, k
    COMPLEX (KIND=dp), DIMENSION(3,3) :: int1, int2, int3
    COMPLEX (KIND=dp), DIMENSION(nedgestot) :: alpha, beta

    e(:) = 0.0_dp
    h(:) = 0.0_dp

    k = ri*omega/c0

    alpha = x(1:nedgestot)
    beta = x((nedgestot+1):(2*nedgestot))

    ! Coefficients of partial integrals.
    c1 = (0,1)*omega*mu0
    c2 = 1.0_dp/((0,1)*omega*eps0*(ri**2))
    
    DO n=1,mesh%nfaces

       DO ns=1,SIZE(ga)
          int1 = intK2(r, n, mesh, k, ga(ns), prd, .TRUE.)
          int2 = intK3(r, n, mesh, k, ga(ns), prd, .TRUE.)
          int3 = intK4(r, n, mesh, k, ga(ns), 0, prd, .TRUE.)
       
          DO q=1,3
             index = mesh%faces(n)%edge_indices(q)
             index = mesh%edges(index)%parent_index
          
             
             e = e + alpha(index)*(ga(ns)%ef(nf)*(ga(ns)%detj**2)*c1*int1(:,q)&
                  + ga(ns)%ef(nf)*c2*int2(:,q)) +&
                  ga(ns)%ef(nf)*ga(ns)%detj*beta(index)*int3(:,q)

             h = h + beta(index)*(ga(ns)%ef(nf)*ga(ns)%detj*int1(:,q)/c2&
                  + ga(ns)%ef(nf)*ga(ns)%detj*int2(:,q)/c1) -&
                  ga(ns)%ef(nf)*(ga(ns)%detj**2)*alpha(index)*int3(:,q)
          END DO
       END DO
    END DO
  END SUBROUTINE scat_fields_frag

  SUBROUTINE field_mesh(name, mesh, scale, nedgestot, x, ga, omega, ri)
    CHARACTER (LEN=*), INTENT(IN) :: name
    TYPE(mesh_container), INTENT(IN) :: mesh
    REAL (KIND=dp), INTENT(IN) :: scale, omega
    COMPLEX (KIND=dp), DIMENSION(:,:), INTENT(IN) :: x
    TYPE(group_action), DIMENSION(:), INTENT(IN) :: ga
    INTEGER, INTENT(IN) :: nedgestot
    COMPLEX (KIND=dp), INTENT(IN) :: ri

    INTEGER :: n, q, index, nf, nga, na
    COMPLEX (KIND=dp), DIMENSION(3) :: et
    COMPLEX (KIND=dp), DIMENSION(mesh%nfaces*SIZE(ga)) :: en
    COMPLEX (KIND=dp) :: eps
    REAL (KIND=dp), DIMENSION(mesh%nfaces*SIZE(ga)) :: eta
    REAL (KIND=dp), DIMENSION(3) :: fn
    CHARACTER (LEN=256) :: oname, numstr
    TYPE(mesh_container) :: mesh2

    WRITE(*,*) 'Computing near fields on particle mesh.'

    eps = (ri**2)*eps0

    en(:) = 0.0_dp

    nga = SIZE(ga)

    mesh2%nnodes = mesh%nnodes*nga
    mesh2%nfaces = mesh%nfaces*nga
    ALLOCATE(mesh2%nodes(mesh2%nnodes))
    ALLOCATE(mesh2%faces(mesh2%nfaces))

    DO na=1,nga
       DO n=1,mesh%nnodes
          mesh2%nodes(n + mesh%nnodes*(na-1))%p = MATMUL(ga(na)%j, mesh%nodes(n)%p)
       END DO

       DO n=1,mesh%nfaces
          mesh2%faces(n + mesh%nfaces*(na-1))%node_indices(:) = &
               mesh%faces(n)%node_indices(:) + mesh%nnodes*(na-1)
       END DO
    END DO

    DO na=1,nga
       DO n=1,mesh%nfaces
          
          et(:) = 0.0_dp
          
          DO nf=1,nga
             DO q=1,3
                index = mesh%faces(n)%edge_indices(q)
                index = mesh%edges(index)%parent_index

                fn = MATMUL(ga(na)%j, rwg(mesh%faces(n)%cp, n, q, mesh))
                
                et = et + fn*x(nedgestot + index, nf)*ga(na)%ef(nf)*ga(na)%detj
                en(n + mesh%nfaces*(na-1)) = en(n + mesh%nfaces*(na-1)) +&
                     rwgDiv(n, q, mesh)*x(index, nf)*ga(na)%ef(nf)
             END DO
          END DO
          
          eta(n + mesh%nfaces*(na-1)) = normc(et)          
       END DO

    END DO

    en(:) = en(:)/((0,1)*omega*eps)

    CALL save_field_msh(name, mesh2, en, eta, scale)

    DEALLOCATE(mesh2%nodes, mesh2%faces)

  END SUBROUTINE field_mesh
END MODULE nfields