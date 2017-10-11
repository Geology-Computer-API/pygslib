"""
PyGSLIB nonlinear, Module with function for nonlinear geostatistics  

Copyright (C) 2015 Adrian Martinez Vargas 

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
any later version.
   
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
   
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>

Code based on paper

    A Step by Step Guide to Bi-Gaussian Disjunctive Kriging, by 
    Julian M. Ortiz, Bora Oz, Clayton V. Deutsch
    Geostatistics Banff 2004
    Volume 14 of the series Quantitative Geology and Geostatistics pp 1097-1102

See also
--------
 - http://www.ccgalberta.com/ccgresources/report05/2003-107-dk.pdf
 - http://www.ccgalberta.com/ccgresources/report04/2002-106-hermite.pdf
 - http://www.ccgalberta.com/ccgresources/report06/2004-112-inference_under_mg.pdf
 - Mining Geostatistics: A. G. Journel, Andre G. Journel, C. J
 - Introduction to disjunctive Kriging and non linear geostatistcs http://cg.ensmp.fr/bibliotheque/public/RIVOIRARD_Cours_00312.pdf

Warning
-------
This module is experimental, not tested and we are getting some validation
errors in the anamorphosis with declustering data. 

"""

cimport cython
cimport numpy as np
import numpy as np
from scipy.stats import norm
from scipy.optimize import brentq
from libc.math cimport sqrt
from libc.math cimport exp
import pygslib
import matplotlib.pyplot as plt 

# is nan test for cython 
#from libc.math cimport isnan


# almost C version of stnormal 
@cython.boundscheck(False)
cdef float stnormpdf(float x):
    cdef float denom = (2*3.1415926)**.5
    cdef float num = exp(-x**2/2)
    return num/denom


#plotting options
ana_options = {
            'dt_pt_color' : 'grey',
            'dt_pt_line' : '-',
            'dt_pt_label' : 'data',
            'ex_pt_color' : 'black',
            'ex_pt_line' : '--',
            'ex_pt_label' : 'exp point',
            'ana_pt_color' : 'orange',
            'ana_pt_line' : '--',
            'ana_pt_label' : 'ana point',
            'ex_ana_pt_color' : 'green',
            'ex_ana_pt_line' : '-',
            'ex_ana_pt_label' : 'ana point(fixed)', 
            'ana_blk_color' : 'red',
            'ana_blk_line' : '--',
            'ana_blk_label' : 'ana block',
            'ex_ana_blk_color' : 'indigo',
            'ex_ana_blk_line' : '-', 
            'ex_ana_blk_label' : 'ana block(fixed)', }    
    
    
# ----------------------------------------------------------------------
#   Transformation table
# ----------------------------------------------------------------------
cpdef ttable(z, w):
    """ttable(z, w)
    
    Creates a transformation table. 
    
    Parameters
    ---------
    z,w : 1D numpy arrays of floats 
        Variable and declustering weight.
    Returns:
    transin,transout : 1D numpy arrays with pairs of raw and gaussian values
    
    Note: 
    This function uses gslib.__dist_transf.ns_ttable
    """
    cdef int error
    
    transin,transout, error = pygslib.gslib.__dist_transf.ns_ttable(z,w)
    
    assert error < 1, 'There was an error = {} in the function gslib.__dist_transf.ns_ttable'.format(error)
    
    
    return transin,transout
        
# ----------------------------------------------------------------------
#   Normal score
# ----------------------------------------------------------------------
cpdef nscore(z, transin, transout, getrank=False):
    """nscore(z, transin,transout, getrank)
    
    Normal score transformation, as in GSLIB
    
        
    Parameters
    ---------
    z : 1D numpy array of floats 
        Variable to transform.
    transin,transout : 1D numpy arrays of floats
        transformation table as obtained in function ttable
        
    Returns
    -------
    y : 1D numpy array of floats
        normal score transformation of variable z
    
    Note: 
    This function uses gslib.__dist_transf.nscore
    """   
    return pygslib.gslib.__dist_transf.nscore(z,transin,transout,getrank)
    
# ----------------------------------------------------------------------
#   Back transform using TTable 
# ----------------------------------------------------------------------
cpdef backtr(y, transin, transout, ltail, utail, ltpar, utpar, zmin, zmax, getrank=False):
    """nscore(z, transin,transout, getrank)
    
    Normal score transformation, as in GSLIB
    
        
    Parameters
    ---------
    y : 1D numpy array of floats 
        Gaussian values.
    transin,transout : 1D numpy arrays of floats
        transformation table as obtained in function ttable
    ltail : integer
    utail : integer
    ltpar : float
    utpar : float
    zmin : float
    zmax : float
    getrank : Boolean default False
    
    
    
    Returns
    -------
    z : 1D numpy array of floats
        raw transformation of gaussian variable y
    
    Note: 
    This function uses gslib.__dist_transf.backtr
    """   
    cdef int error
    
    z, error= pygslib.gslib.__dist_transf.backtr(vnsc = y, transin = transin, transout = transout, 
                                            ltail = ltail,
                                            utail = utail, # 4 is hyperbolic
                                            ltpar = ltpar,
                                            utpar = utpar,
                                            zmin = zmin,
                                            zmax = zmax, 
                                            getrank = getrank)
    
    assert error < 1, 'There was an error = {} in the function gslib.__dist_transf.backtr'.format(error)  

    return z
    
# ----------------------------------------------------------------------
#   Report some sats from declusterd dataset
# ----------------------------------------------------------------------
cpdef stats(z, w, iwt = True, report = True):
    """stats(z, w)
    
    Reports some basic stats using declustering wights 
    
    Parameters
    ---------
    z,w : 1D numpy arrays of floats 
        Variable and declustering weight.
    iwt: boolean default True
        If True declustering weights will be used to calculate statsistics
    report : boolean default True
        If True a printout will be produced

    Returns:
    xmin,xmax, xcvr,xmen,xvar : floats
        minimum, maximum, coefficient of variation, media and variance
    
    Note: 
    This function uses gslib.__plot.probplt to optain the stats
    """
    cdef int error
    
    parameters_probplt = {
            'iwt'  : iwt,     #int, 1 use declustering weight
            'va'   : z,       # array('d') with bounds (nd)
            'wt'   : w}       # array('d') with bounds (nd), wight variable (obtained with declust?)



    binval,cl,xpt025,xlqt,xmed,xuqt,xpt975,xmin,xmax, xcvr,xmen,xvar,error = pygslib.gslib.__plot.probplt(**parameters_probplt)
    
    assert error < 1, 'There was an error = {} in the function gslib.__dist_transf.ns_ttable'.format(error)
    
    if report:
        print  'Stats Summary'
        print  '-------------'
        print  'Minimum        ', xmin
        print  'Maximum        ', xmax
        print  'CV             ', xcvr
        print  'Mean           ', xmen
        print  'Variance       ', xvar
        print  'Quantiles 2.5-97.5' , [xpt025,xlqt,xmed,xuqt,xpt975]
        
    return xmin,xmax, xcvr,xmen,xvar 
    
    
    
# ----------------------------------------------------------------------
#   Functions for punctual gaussian anamorphosis 
# ----------------------------------------------------------------------

#the recurrent formula for normalized polynomials
cpdef recurrentH(np.ndarray [double, ndim=1] y, int K=30):
    """recurrentH(np.ndarray [double, ndim=1] y, int K=30)
    
    Calculates the hermite polynomials with the recurrent formula
    
    Parameters
    ----------
    y : 1D array of float64
        Gaussian values calculated for the right part of the bin.
    K  : int32, default 30
        Number of hermite polynomials 

    Returns
    -------
    H : 2D array of float64
        Hermite monomials H(i,y) with shape [K+1,len(y)]
      
    See Also
    --------
    pygslib.gslib.__dist_transf.anatbl
       
    Note
    ----  
    The `y` values may be calculated on the right side of the bin, 
    as shown in fig VI.13, page 478 of Mining Geostatistics: 
    A. G. Journel, Andre G. Journel, C. J. The function 
    pygslib.gslib.__dist_transf.anatbl was prepared to provide these values,
    considering declustering weight if necessary. 
    
    The results from pygslib.gslib.__dist_transf.ns_ttable are inappropriate 
    for this calculation because are the mid interval in the bin.  
    """
    assert(K>=1)
    
    cdef np.ndarray [double, ndim=2] H
    cdef int k
    
    H=np.ones((K+1,len(y))) 
    #H[0,:]=1                #first monomial already ones 
    H[1,:]=-y               #second monomial
    
    # recurrent formula
    for k in range(1,K):
        H[k+1,:]= -1/np.sqrt(k+1)*y*H[k,:]-np.sqrt(k/float(k+1))*H[k-1,:]
    
    return H   #this is a 2D array of H (ki,yi)


#fit PCI for f(x)=Z(x)
cpdef fit_PCI(np.ndarray [double, ndim=1] z,
              np.ndarray [double, ndim=1] y,
              np.ndarray [double, ndim=2] H,
              double meanz=np.nan):
    """fit_PCI(np.ndarray [double, ndim=1] z, np.ndarray [double, ndim=1] y, np.ndarray [double, ndim=2] H, float meanz=np.nan)  
     
    Fits the hermite coefficient (PCI) 
    
    Parameters
    ----------
    z  : 1D array of float64
        Raw values sorted
    y  : 1D array of float64
        Gaussian values calculated for the right part of the bin.
    meanz: float64, default np.nan
        mean of z, if NaN then the mean will be calculated as np.mean(z)

    Returns
    -------
    PCI : 1D array of floats
        Hermite coefficients or PCI 
    g   : 1D array of floats
        pdf value (g[i]) corresponding to each gaussian value (y[i])
      
    See Also
    --------
    var_PCI
       
    Note
    ---- 
    ``PCI[0]=mean(z)`` and  ``sum=(PCI[1...n]^2)``. To validate the fit 
    calculate the variance with the function ``var_PCI()`` and compare 
    it with the experimental variance of `z`. You may also validate the 
    fit by calculating ``error= z-PHI(y)``, where ``PHI(y)`` are the 
    `z'` values calculated with the hermite polynomial expansion.  
    
    """
    
    assert y.shape[0]==z.shape[0]==H.shape[1], 'Error: wrong shape on input array'
    
    cdef np.ndarray [double, ndim=1] PCI
    cdef np.ndarray [double, ndim=1] g
    
    cdef unsigned int i, p, j, n=H.shape[0], m=H.shape[1]
    
    # if no mean provided
    if np.isnan(meanz):
        meanz = np.mean(z)
    
    PCI=np.zeros([H.shape[0]])
    g=np.zeros([H.shape[1]])
    PCI[0]=np.mean(z)
    
    for p in range(1,n):
        for i in range(1,m):
            g[i]= stnormpdf(y[i])
            PCI[p]=PCI[p] + (z[i-1]-z[i])*1/sqrt(p)*H[p-1,i]*g[i]
    
    return PCI, g


#get variance from PCI
cpdef var_PCI(np.ndarray [double, ndim=1] PCI):
    """var_PCI(np.ndarray [double, ndim=1] PCI) 
     
    Calculates the variance from hermite coefficient (PCI) 
     
    Parameters
    ----------
    PCI : 1D array of float64
        hermite coefficient

    Returns
    -------
    var : float64
        variance calculated with hermite polynomials
      
    See Also
    --------
    fit_PCI
       
    Note
    ----  
    The output may be used for validation of the PCI coefficients, it 
    may be close to the experimental variance of z.
    
    """
    
    a=PCI[1:]**2
    return np.sum(a)

#expand anamorphosis
cpdef expand_anamor(np.ndarray [double, ndim=1] PCI, 
                    np.ndarray [double, ndim=2] H,
                    double r=1.):
    """expand_anamor(np.ndarray [double, ndim=1] PCI, np.ndarray [double, ndim=2] H, double r=1.)
    
    Expands the anamorphosis function, that is :math:`Z = \sum_p(PSI_p*r^p*Hp(Yv))`
    
    r is the support effect. If r = 1 Z with point support will returned. 
    
    
    Parameters
    ----------
    PCI : 1D array of floats
        hermite coefficient
    H : 2D array of floats
        Hermite monomials H(i,y) with shape [K+1,len(y)]. See recurrentH
    r : float, default 1
        the support effect

    Returns
    -------
    PCI : 1D array of floats
        Hermite coefficients or PCI 
      
    See Also
    --------
    recurrentH
      
  
    """
    
    cdef np.ndarray [double, ndim=1] Z
    cdef int p
        
    Z=np.zeros(H.shape[1])
    Z[:]=PCI[0]
    for p in range(1,len(PCI)):
        Z+=PCI[p]*H[p,:]*r**p
    
    return Z

# ----------------------------------------------------------------------
#   Helper functions to preprocess punctual/experimental gaussian anamorphosis 
# ----------------------------------------------------------------------

     
# Back transformation from anamorphosis
# TODO: remove fluctuations before transforming
cpdef Y2Z(np.ndarray [double, ndim=1] y,
        np.ndarray [double, ndim=1] PCI,
        double zamin, 
        double yamin, 
        double zpmin, 
        double ypmin, 
        double zpmax, 
        double ypmax, 
        double zamax, 
        double yamax,
        double r=1):
    """Y2Z(np.ndarray [double, ndim=1] y, np.ndarray [double, ndim=1] PCI, double zamin, double yamin, double zpmin, double ypmin, double zpmax, double ypmax, double zamax, double yamax, double r=1)
    
    Gaussian (Y) to raw (Z) transformation 
    
    This is a convenience functions. It calls H=recurrentH(K,Y) and
    then returns Z = expand_anamor(PCI,H,r). K is deduced from 
    PCI.shape[0]. It also linearly interpolates the values
    out of the control points. 
    
    
    Parameters
    ----------
    PCI : 1D array of float64
        hermite coefficient
    y : 1D array of float64
        Gaussian values
    r : float64, default 1
        the support effect
    ypmin,zpmin,ypmax,zpmax : float64
         z, y practical minimum and maximum
    yamin,zamin,yamax,zamax : float64
         z, y authorized minimum and maximum

    Returns
    -------
    Z : 1D array of floats
        raw values corresponding to Y 
      
    See Also
    --------
    recurrentH, expand_anamor
       
    
    """
    
    cdef int K
    cdef np.ndarray [double, ndim=2] H
    cdef np.ndarray [double, ndim=1] Z
    cdef np.ndarray [double, ndim=1] zapmin= np.array([zamin,zpmin])
    cdef np.ndarray [double, ndim=1] yapmin= np.array([yamin,ypmin])
    cdef np.ndarray [double, ndim=1] zapmax= np.array([zpmax,zamax])
    cdef np.ndarray [double, ndim=1] yapmax= np.array([ypmax,yamax])

    
    K=PCI.shape[0]-1
    H=recurrentH(y,K)
    Z=expand_anamor(PCI,H,r)
    
    # fix some values based on the control points
    for i in range(y.shape[0]): 
        if y[i]<=ypmin:  
            Z[i]=np.interp(y[i], xp=yapmin, fp=zapmin)
            continue 
            
        if y[i]>=ypmax:  
            Z[i]=np.interp(y[i], xp=yapmax, fp=zapmax)
            continue 
        
    #and the new Z values with the existing PCI
    return Z

# Transformation from anamorphosis
# TODO: remove fluctuations before transforming
cpdef Z2Y_linear(np.ndarray [double, ndim=1] z,
                 np.ndarray [double, ndim=1] zm,
                 np.ndarray [double, ndim=1] ym,
                 double zamin, 
                 double yamin, 
                 double zpmin, 
                 double ypmin, 
                 double zpmax, 
                 double ypmax, 
                 double zamax, 
                 double yamax):
    """Z2Y_linear(np.ndarray [double, ndim=1] z, np.ndarray [double, ndim=1] zm, np.ndarray [double, ndim=1] ym, double zamin, double yamin, double zpmin, double ypmin, double zpmax, double ypmax, double zamax, double yamax) 
             
    Raw (Z) to Gaussian (Y) transformation 
    
    Given a set of pairs [zm,ym] representing an experimental 
    Gaussian anamorphosis, this functions linearly interpolate y values 
    corresponding to z within the [zamin, zamax] intervals
    
    Parameters
    ----------
    z : 1D array of float64
        raw (Z) values where we want to know Gaussian (Y) equivalent
    zm,ym : 1D array of float64
        tabulated [Z,Y] values
    ypmin, zpmin, ypmax, zpmax : float64
         z, y practical minimum and maximum
    yamin, zamin, yamax,zamax : float64
         z, y authorized minimum and maximum

    Returns
    -------
    Z : 1D array of float64
        raw values corresponding to Y 
      
    See Also
    --------
    Y2Z
       
    
    """    
    
    cdef np.ndarray [double, ndim=1] Y=np.zeros(z.shape[0])
    cdef np.ndarray [double, ndim=1] zapmin= np.array([zamin,zpmin])
    cdef np.ndarray [double, ndim=1] yapmin= np.array([yamin,ypmin])
    cdef np.ndarray [double, ndim=1] zapmax= np.array([zpmax,zamax])
    cdef np.ndarray [double, ndim=1] yapmax= np.array([ypmax,yamax])

    
    # fix some values based on the control points
    for i in range(z.shape[0]): 
        
        if z[i]<=zamin:  
            Y[i]=yamin
            continue 

        if z[i]>=zamax:  
            Y[i]=yamax
            continue 
        
        if z[i]<=zpmin:  
            Y[i]=np.interp(z[i], xp=zapmin, fp=yapmin)
            continue 
            
        if z[i]>=zpmax:  
            Y[i]=np.interp(z[i], xp=zapmax, fp=yapmax)
            continue 
        
        if z[i]<zpmax and z[i]>zpmin:  
            Y[i]=np.interp(z[i], xp=zm, fp=ym)
            continue
        
    return Y

# ----------------------------------------------------------------------
#   Interactive gaussian anamorphosis modeling 
# ----------------------------------------------------------------------
cpdef calautorized(zana, zraw, gauss, zpmin=None, zpmax=None):

    cdef int i
    cdef int j
    
    cdef int ii
    cdef int jj

    if zpmin is None:
        zpmin = min(zraw)

    if zpmax is None:
        zpmax = max(zraw)
        
    #get index for zpmax
    for jj in range(zraw.shape[0]-1, 0, -1):
        if zraw[jj]<zpmax:
            break
            
    #get index for zpmin
    for ii in range(0, zraw.shape[0]-1):
        if zraw[ii]>zpmin:
            break        
     
    # get index for minimum authorized
    for i in range(zana.shape[0]/2, 1, -1): 
        
        if zana[i-1] < zraw[ii] or zana[i-1] > zana[i] or gauss[i-1]<gauss[ii]:
            break
    
    # get index for maximum authorized
    for j in range(zana.shape[0]/2, zana.shape[0]-1, +1): 
        
        if zana[j+1] > zraw[jj] or zana[j+1] < zana[j] or gauss[j+1]>gauss[jj]:
            break 
        
    return i, j, ii, jj 

    
cpdef calautorized_blk(zana, gauss, zpmin, zpmax):

    cdef int i
    cdef int j
    
    cdef int ii
    cdef int jj
        
    #get index for zpmax
    jj = zana.shape[0]-1
    #get index for zpmin
    ii = 0        
     
    # get index for minimum authorized
    for i in range(zana.shape[0]/2, 1, -1): 
        
        if zana[i-1] < zpmin or zana[i-1] > zana[i] or gauss[i-1]<gauss[ii]:
            break
    
    # get index for maximum authorized
    for j in range(zana.shape[0]/2, zana.shape[0]-1, +1): 
        
        if zana[j+1] > zpmax or zana[j+1] < zana[j] or gauss[j+1]>gauss[jj]:
            break 
        
    return i, j, ii, jj 

cpdef findcontrolpoints(zana, zraw, gauss, zpmin, zpmax, zamin, zamax):

    cdef int i
    cdef int j

    cdef int ii
    cdef int jj
    
    assert zamax < zamin
    assert zpmax < zpmin
    assert zamax <= zpmax
    assert zamin >= zpmin
        
    #get index for zpmax
    for jj in range(zraw.shape[0]-1, 0, -1):
        if zraw[jj]<=zpmax:
            break
            
    #get index for zpmin
    for ii in range(0, zraw.shape[0]-1):
        if zraw[ii]>=zpmin:
            break        
     
    # get index for zamin
    for i in range(zana.shape[0]/2, 1, -1): 
        
        if zana[i-1] <= zamin:
            break
    
    # get index for zamax
    for j in range(zana.shape[0]/2, zana.shape[0]-1, +1): 
        
        if zana[j+1] >= zamax :
            break  

    assert zana[j] <= zraw[jj], 'Error: calculated zamax > calculated zpmax'
    assert zana[i] >= zraw[ii], 'Error: calculated zamin < calculated zpmin'
    assert gauss[j] <= gauss[jj], 'Error: calculated yamax > calculated ypmax'
    assert gauss[i] >= gauss[ii], 'Error: calculated yamin < calculated ypmin'    
    
    
    return i, j, ii, jj 


    
# Interactive anamorphosis modeling, including some plots
# TODO: improve control points, authorized limits and practical limits
# Note: Allow using transformation table with max and min over practical and authorized limits
#      this allows for PCI coefficients to fit better the experimental variance. 
def anamor(z, w, ltail=1, utail=1, ltpar=1, utpar=1, K=30, 
             zmin=None, zmax=None, ymin=None, ymax=None,
             zamin=None, zamax=None, zpmin=None, zpmax=None,
             ndisc = 1000, **kwargs):
    """anamor(z, w)
    """
    # set colors and line type
    options = ana_options
    options.update(kwargs)
    
    # z min and max for anamorphosis calculation
    if zmin==None:
        zmin = np.min(z)
        
    if zmax==None:
        zmax = np.max(z)
    
    # z min and max on any output... 
    if zpmin==None:
        zpmin = np.min(z)
        
    if zpmax==None:
        zpmax = np.max(z)
    
    
    # a) get experimental transformation table
    transin, transout = ttable(z, w)
    
    if ymin==None:
        ymin = np.min(transout)
        
    if ymax==None:
        ymax = np.max(transout)
    
    
    # b) genarate a sequence of gaussian values
    gauss = np.linspace(ymin,ymax, ndisc)
    
    # c) Get the back tansform using normal score transformation
    raw = pygslib.nonlinear.backtr(y = gauss, 
                                   transin = transin, 
                                   transout = transout, 
                                   ltail = ltail,
                                   utail = utail, # 4 is hyperbolic
                                   ltpar = ltpar,
                                   utpar = utpar,
                                   zmin = zmin,
                                   zmax = zmax,
                                   getrank = False)
                                   
    # d) get Hermite expansion
    H=  pygslib.nonlinear.recurrentH(y=gauss, K=K)
    
    # e) Get PCI
    xmin,xmax,xcvr,xmen,xvar = pygslib.nonlinear.stats(z,w,report=False)
    PCI, g =  pygslib.nonlinear.fit_PCI( raw, gauss,  H, meanz=np.nan)
    PCI[0] = xmen
    raw_var = xvar
    PCI_var = var_PCI(PCI)
    
    # f) Plot transformation
    zana = expand_anamor(PCI, H, r=1)
    
    if zamax is None or zamin is None:
        i, j, ii, jj = calautorized(zana=zana,
                                     zraw=raw, 
                                     gauss=gauss,
                                     zpmin=zpmin, 
                                     zpmax=zpmax)
    else: 
        i, j, ii, jj = findcontrolpoints(zana=zana,
                                     zraw  = raw, 
                                     gauss = gauss,
                                     zpmin = zpmin, 
                                     zpmax = zpmax,
                                     zamin = zamin,
                                     zamax = zamax)

    # d) Now we get the transformation table for gaussian anamorphosis corrected
    Z = pygslib.nonlinear.backtr(  y = gauss, 
                                   transin = zana[i:j+1], 
                                   transout = gauss[i:j+1], 
                                   ltail = ltail,
                                   utail = utail, # 4 is hyperbolic
                                   ltpar = ltpar,
                                   utpar = utpar,
                                   zmin = raw[ii],
                                   zmax = raw[jj],
                                   getrank = False)
    
    # plot results
    fig = plt.figure()
    ax = fig.add_subplot(111)
    plt.ylabel('Z')
    plt.xlabel('Y')
    ax.plot(transout, transin, options['dt_pt_line'], color = options['dt_pt_color'], linewidth=4.0, label = options['dt_pt_label'])
    ax.plot(gauss[1:-1],raw[1:-1], options['ex_pt_line'], color = options['ex_pt_color'], label = options['ex_pt_label'])
    ax.plot(gauss[1:-1],zana[1:-1], options['ana_pt_line'], color = options['ana_pt_color'], label = options['ana_pt_label'])
    ax.plot(gauss,Z, options['ex_ana_pt_line'], color = options['ex_ana_pt_color'], label = options['ex_ana_pt_label'])
    ax.plot(gauss[i],zana[i], 'or',mfc='none')
    ax.plot(gauss[j],zana[j], 'or',mfc='none')
    ax.plot(gauss[ii],raw[ii], 'ob',mfc='none')
    ax.plot(gauss[jj],raw[jj], 'ob',mfc='none')
    plt.legend(bbox_to_anchor=(1.05, 1), loc=2, borderaxespad=0.)
    
    #plt.plot(transout, transin, 'ok', mfc='none')
    
    print 'Raw Variance', raw_var
    print 'Variance from PCI', PCI_var
    
    print 'zamin', zana[i]
    print 'zamax', zana[j]
    print 'yamin', gauss[i]
    print 'yamax', gauss[j]
    
    print 'zpmin', raw[ii]
    print 'zpmax', raw[jj]
    print 'ypmin', gauss[ii]
    print 'ypmax', gauss[jj]
    
    
    return PCI, H, raw, zana, gauss,Z, raw_var , PCI_var, ax

def anamor_blk( PCI, H, r, gauss, Z,
                  ltail=1, utail=1, ltpar=1, utpar=1,
                  raw=None, zana=None, **kwargs):  
    """
    """
    
    # set colors and line type
    options = ana_options
    options.update(kwargs)
    
    # get practical limits on Z
    zpmin = np.min(Z)
    zpmax = np.max(Z)
    
    # Get Z experimental
    z_v= expand_anamor(PCI, H, r)
    
    # Get authorized limits on z experimental
    i, j, ii, jj = calautorized_blk( zana=z_v, 
                                     gauss=gauss,
                                     zpmin=zpmin, 
                                     zpmax=zpmax)

    # Now we get the transformation table corrected
    ZV = pygslib.nonlinear.backtr( y = gauss, 
                                   transin = z_v[i:j+1], 
                                   transout = gauss[i:j+1], 
                                   ltail = ltail,
                                   utail = utail, # 4 is hyperbolic
                                   ltpar = ltpar,
                                   utpar = utpar,
                                   zmin = zpmin,
                                   zmax = zpmax,
                                   getrank = False)

                                                                
    
    # plot results
    fig = plt.figure()
    ax = fig.add_subplot(111)
    plt.ylabel('Z')
    plt.xlabel('Y')
    
    
    
    if raw is not None: 
        ax.plot(gauss[1:-1],raw[1:-1], options['ex_pt_line'], color = options['ex_pt_color'], label =  options['ex_pt_label'])
    if zana is not None:
        ax.plot(gauss[1:-1],zana[1:-1], options['ana_pt_line'], color = options['ana_pt_color'], label =  options['ana_pt_label'])
    
    ax.plot(gauss[1:-1],Z[1:-1], options['ex_ana_pt_line'], color = options['ex_ana_pt_color'], label =  options['ex_ana_pt_label'])
    
    ax.plot(gauss[1:-1],z_v[1:-1], options['ana_blk_line'], color = options['ana_blk_color'], label =  options['ana_blk_label'])
    
    ax.plot(gauss,ZV, options['ex_ana_blk_line'], color = options['ex_ana_blk_color'], label =  options['ex_ana_blk_label'])
    
    ax.plot(gauss[i],z_v[i], 'or',mfc='none')
    ax.plot(gauss[j],z_v[j], 'or',mfc='none')
    ax.plot(gauss[ii],ZV[ii], 'ob',mfc='none')
    ax.plot(gauss[jj],ZV[jj], 'ob',mfc='none')
    
    plt.legend(bbox_to_anchor=(1.05, 1), loc=2, borderaxespad=0.)

    return ZV
    
    
# Direct anamorphosis modeling from raw data
def anamor_raw(z, w, K=30, **kwargs):
    """anamor(z, w)
    """ 
    # set colors and line type
    options = ana_options
    options.update(kwargs)

    
    # a) get experimental transformation table
    raw, gauss = ttable(z, w)   
                                   
    # b) get Hermite expansion
    H=  pygslib.nonlinear.recurrentH(y=gauss, K=K)
    
    # e) Get PCI
    xmin,xmax,xcvr,xmen,xvar = pygslib.nonlinear.stats(z,w,report=False)
    PCI, g =  pygslib.nonlinear.fit_PCI( raw, gauss,  H, meanz=np.nan)
    PCI[0] = xmen
    raw_var = xvar
    PCI_var = var_PCI(PCI)
    
    # f) Plot transformation
    zana = pygslib.nonlinear.Y2Z(gauss, PCI, 
                           zamin = raw.min(), 
                           yamin = gauss.min(),  
                           zpmin = raw.min(),  
                           ypmin = gauss.min(), 
                           zpmax = raw.max(), 
                           ypmax = gauss.max(), 
                           zamax = raw.max(),
                           yamax = gauss.max(),
                           r=1.)    

                           
    fig = plt.figure()
    ax = fig.add_subplot(111)
    plt.ylabel('Z')
    plt.xlabel('Y')
    ax.plot(gauss,raw, options['dt_pt_line'], color = options['dt_pt_color'], linewidth=4.0, label = options['dt_pt_label'])
    ax.plot(gauss,zana, options['ana_pt_line'], color = options['ana_pt_color'], label = options['ana_pt_label'])
    plt.legend(bbox_to_anchor=(1.05, 1), loc=2, borderaxespad=0.)
    
    print 'Raw Variance', raw_var
    print 'Variance from PCI', PCI_var
    
    return PCI, H, raw, zana, gauss, raw_var , PCI_var, ax
    

# ----------------------------------------------------------------------
#   Extra Functions for support and information effect  
# ----------------------------------------------------------------------
cpdef f_var_Zv(double r,
               np.ndarray [double, ndim=1] PCI,
               double Var_Zv=0):
    """f_var_Zv(double r, np.ndarray [double, ndim=1] PCI, double Var_Zv=0)
    
    This is an internal function used to deduce the coefficients r
    (or s), representing the support effect. It defines the relations:  
    
    
        :math:`Var(Zv) = \sum PCI^2 * r^(n*2)`
        
        or 
    
        :math:`Var(Zv*) = \sum PCI^2 * s^(n*2)`
    
    r is necessary to account for information effect
    s is necessary to account for smoothing in the information effect.        
        
    see "The information effect and estimating recoverable reserves"
    J. Deraisme (Geovariances), C. Roth (Geovariances) for more information
    
    Parameters
    ----------
    r : float64
        r or s coefficient representing support effect of Zv (or Zv*)
    PCI : 1D array of floats
        hermite coefficients
    Var_Zv : float64
        Block Variance var(Zv) or var(Zv*) 
    
    Note
    ----
    var(Zv) can be calculated as C(0)-gamma(v,v) or C(v,v) see function 
    block_covariance 
    
    var(Zv*) = var(Zv) - Kriging variance - 2*LaGrange multiplier
     
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    
    """
    
    cdef float a 
    cdef int i
    
    a=0.
    
    for i in range(1,len(PCI)):
       a+=PCI[i]**2. * r**(2.*i)
    return a-Var_Zv

# this is to pass a function to brentq
# auxiliar function covar (Zv,Zv*) = sum PCI^2 * r^n * s^n * ro^n 
# see "The information effect and estimating recoverable reserves"
# J. Deraisme (Geovariances), C. Roth (Geovariances)
cpdef f_covar_ZvZv(double ro,
                   double s,
                   double r,
                   np.ndarray [double, ndim=1] PCI,
                   double Covar_ZvZv=0):
    """f_covar_ZvZv(double ro, double s, double r, np.ndarray [double, ndim=1] PCI, double Covar_ZvZv=0)
    
    This is an internal function used to deduce the coefficients 
    ro = covar(Yv, Yv*). This function represents the expression:  
    
    
        :math:`Covar (Zv,Zv^*) = \sum PCI^2 * r^n * s^n * ro^n`
        
    ro is necessary to account for the conditional bias in the 
    information effect.     
        
    see "The information effect and estimating recoverable reserves"
    J. Deraisme (Geovariances), C. Roth (Geovariances) for more information
    
    Parameters
    ----------
    r, ro, s : float
        support effect and information effect coefficients.
    PCI : 1D array of floats
        hermite coefficients
    Covar_ZvZv : float
        Block covariance (correlation) between true Zv and estimate Zv* 
    
    Note
    ----
    :math:`Covar (Zv,Zv^*) = var(Zv) - Kriging variance - LaGrange multiplier`
    
    see expression 7.47, page 97 on Basic Linear Geostatistics by 
    Margaret Armstrong.
    
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    Note that the slop of regression is  
    
    :math:`p = Covar (Zv,Zv*) / (Covar (Zv,Zv*)  - LaGrange multiplier)`
    
    """
    
    cdef float a 
    cdef int i
    
    a=0.
    
    for i in range(1,len(PCI)):
       a+=PCI[i]**2. * r**i * s**i * ro**i
    return a-Covar_ZvZv


#calculate support effect coefficient r
cpdef get_r(double Var_Zv,
            np.ndarray [double, ndim=1] PCI):
    """get_r(double Var_Zv, np.ndarray [double, ndim=1] PCI)
    
    This function deduces the value of the support effect coefficient r
    or the information effect coefficient, smoothing component, s 
    defined by the equations: 
    
        :math:`Var(Zv) = \sum PCI^2 * r^(n*2)`
        
        and
    
        :math:`Var(Zv*) = \sum PCI^2 * s^(n*2)`
    
    
    The value of r is deduced by finding the root of the equation 
    f_var_Zv, using the classic Brent method (see scipy.optimize.brentq) 
    
    
    Parameters
    ----------
    PCI : 1D array of float64
        hermite coefficient
    Var_Zv : float64
        Block variance

    Returns
    -------
    r :  float64
        support effect coefficient r or information effect coefficient s
      
    See Also
    --------
    f_var_Zv, fit_PCI, scipy.optimize.brentq
    
    Note
    ----
    var(Zv) can be calculated as C(0)-gamma(v,v) or C(v,v) see function 
    block_covariance 
    
    var(Zv*) = var(Zv) - Kriging variance - 2*LaGrange multiplier
     
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    """
    
    return brentq(f=f_var_Zv, a=0, b=1, args=(PCI,Var_Zv))

#calculate information effect coefficient ro
cpdef get_ro(double Covar_ZvZv,
           np.ndarray [double, ndim=1] PCI,
           double r,
           double s):
    """get_ro(double Covar_ZvZv, np.ndarray [double, ndim=1] PCI, double r, double s)
    
    This function deduces the information effect coefficient, 
    conditional bias component, ro defined by the equations: 
    
        :math:`Covar (Zv,Zv^*) = \sum PCI^2 * r^n * s^n * ro^n`
        
    ro is necessary to account for the conditional bias in the 
    information effect.     
        
    The value of ro is deduced by finding the root of the equation 
    f_covar_ZvZv, using the classic Brent method (see 
    scipy.optimize.brentq)
    
    Parameters
    ----------
    r, s : float
        support effect and information effect (smoothing component)
    PCI : 1D array of floats
        hermite coefficients
    Covar_ZvZv : float
        Block covariance (correlation) between true Zv and estimate Zv* 
    
    Note
    ----
    :math:`Covar (Zv,Zv*) = var(Zv) - Kriging variance - LaGrange multiplier`
    
    see expression 7.47, page 97 on Basic Linear Geostatistics by 
    Margaret Armstrong.
    
    In case of information effect this can be calculated with a dummy 
    dataset in a single block representing future information, for 
    example blast holes. 
    
    Note that the slop of regression is  
    
    :math:`p = Covar (Zv,Zv^*) / (Covar (Zv,Zv^*)  - LaGrange multiplier)`
    
    """
    
    return brentq(f=f_covar_ZvZv, a=0, b=1, args=(s,r,PCI,Covar_ZvZv))



# ----------------------------------------------------------------------
#   Uniform conditioning functions
# ----------------------------------------------------------------------

#cpdef recurrentU(np.ndarray [double, ndim=2] H, float yc):
    
#    U =  H 
"""
cpdef ucondit(np.ndarray [double, ndim=1] ZV,
              np.ndarray [double, ndim=1] PCI, 
              float zc,
              float r=1., 
              float R=1., 
              float ro=1.): 
    
    
    # r block support, R panel support, ro info effect  
    
    
    cdef float t
    cdef int K
    cdef np.ndarray [double, ndim=1] T, Q, M
    cdef np.ndarray [double, ndim=2] H
    
    # get general parameters 
    t=R/(r*ro)       # info and support effect (for no info make ro=1)
    K = PCI.shape[0]
    yc = Z2Y_linear 
    YV = Z2Y_linear
    
    H = recurrentH(YV, K)
    
    T[:] = 1- norm.pdf((yc-t*YV)/np.sqrt(1-t**2))
    
    Q = np.zeros ([ZV.shape[0]])
    
    for i in range(K):
        for j in range(K): 
            Q = Q + t**i*H[i][:] * PCI[j]*r**j*ro**j
    
    #M = Q / T
    
    return T, Q, M
    
"""
