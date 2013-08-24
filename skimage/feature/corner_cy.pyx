#cython: cdivision=True
#cython: boundscheck=False
#cython: nonecheck=False
#cython: wraparound=False
import numpy as np
cimport numpy as cnp
from libc.float cimport DBL_MAX

from skimage.color import rgb2grey
from skimage.util import img_as_float


def corner_moravec(image, Py_ssize_t window_size=1):
    """Compute Moravec corner measure response image.

    This is one of the simplest corner detectors and is comparatively fast but
    has several limitations (e.g. not rotation invariant).

    Parameters
    ----------
    image : ndarray
        Input image.
    window_size : int, optional (default 1)
        Window size.

    Returns
    -------
    response : ndarray
        Moravec response image.

    References
    ----------
    ..[1] http://kiwi.cs.dal.ca/~dparks/CornerDetection/moravec.htm
    ..[2] http://en.wikipedia.org/wiki/Corner_detection

    Examples
    --------
    >>> from skimage.feature import moravec, peak_local_max
    >>> square = np.zeros([7, 7])
    >>> square[3, 3] = 1
    >>> square
    array([[ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  1.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.]])
    >>> moravec(square)
    array([[ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  1.,  1.,  1.,  0.,  0.],
           [ 0.,  0.,  1.,  2.,  1.,  0.,  0.],
           [ 0.,  0.,  1.,  1.,  1.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.],
           [ 0.,  0.,  0.,  0.,  0.,  0.,  0.]])
    """

    cdef Py_ssize_t rows = image.shape[0]
    cdef Py_ssize_t cols = image.shape[1]

    cdef double[:, ::1] cimage = np.ascontiguousarray(img_as_float(image))
    cdef double[:, ::1] out = np.zeros(image.shape, dtype=np.double)

    cdef double msum, min_msum
    cdef Py_ssize_t r, c, br, bc, mr, mc, a, b
    for r in range(2 * window_size, rows - 2 * window_size):
        for c in range(2 * window_size, cols - 2 * window_size):
            min_msum = DBL_MAX
            for br in range(r - window_size, r + window_size + 1):
                for bc in range(c - window_size, c + window_size + 1):
                    if br != r and bc != c:
                        msum = 0
                        for mr in range(- window_size, window_size + 1):
                            for mc in range(- window_size, window_size + 1):
                                msum += (cimage[r + mr, c + mc]
                                         - cimage[br + mr, bc + mc]) ** 2
                        min_msum = min(msum, min_msum)

            out[r, c] = min_msum

    return np.asarray(out)


cdef inline double _corner_fast_response(double curr_pixel,
                                         double* circle_intensities,
                                         char* bins, char state, char n):
    cdef char consecutive_count = 0
    cdef double curr_response
    cdef Py_ssize_t l, m
    for l in range(15 + n):
        if bins[l % 16] == state:
            consecutive_count += 1
            if consecutive_count == n:
                curr_response = 0
                for m in range(16):
                    curr_response += abs(circle_intensities[m] - curr_pixel)
                return curr_response
        else:
            consecutive_count = 0
    return 0


def _corner_fast(double[:, ::1] image, char n, double threshold):

    cdef Py_ssize_t rows = image.shape[0]
    cdef Py_ssize_t cols = image.shape[1]

    cdef Py_ssize_t i, j, k

    cdef char speed_sum_b, speed_sum_d
    cdef double curr_pixel
    cdef double lower_threshold, upper_threshold
    cdef double[:, ::1] corner_response = np.zeros((rows, cols),
                                                   dtype=np.double)

    cdef char *rp = [0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3, -3, -3, -2, -1]
    cdef char *cp = [3, 3, 2, 1, 0, -1, -2, -3, -3, -3, -2, -1, 0, 1, 2, 3]
    cdef char bins[16]
    cdef double circle_intensities[16]

    cdef double curr_response

    for i in range(3, rows - 3):
        for j in range(3, cols - 3):

            curr_pixel = image[i, j]
            lower_threshold = curr_pixel - threshold
            upper_threshold = curr_pixel + threshold

            for k in range(16):
                circle_intensities[k] = image[i + rp[k], j + cp[k]]
                if circle_intensities[k] > upper_threshold:
                    # Brighter pixel
                    bins[k] = 'b'
                elif circle_intensities[k] < lower_threshold:
                    # Darker pixel
                    bins[k] = 'd'
                else:
                    # Similar pixel
                    bins[k] = 's'

            # High speed test for n>=12
            if n >= 12:
                speed_sum_b = 0
                speed_sum_d = 0
                for k in range(0, 16, 4):
                    if bins[k] == 'b':
                        speed_sum_b += 1
                    elif bins[k] == 'd':
                        speed_sum_d += 1
                if speed_sum_d < 3 and speed_sum_b < 3:
                    continue

            curr_response = \
                _corner_fast_response(curr_pixel, circle_intensities,
                                      bins, 'b', n)

            if curr_response == 0:
                curr_response = \
                    _corner_fast_response(curr_pixel, circle_intensities,
                                          bins, 'd', n)

            corner_response[i, j] = curr_response

    return np.asarray(corner_response)
