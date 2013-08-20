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

    cdef cnp.ndarray[dtype=cnp.double_t, ndim=2, mode='c'] cimage, out

    if image.ndim == 3:
        cimage = rgb2grey(image)
    cimage = np.ascontiguousarray(img_as_float(image))

    out = np.zeros(image.shape, dtype=np.double)

    cdef double* image_data = <double*>cimage.data
    cdef double* out_data = <double*>out.data

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
                                a = (r + mr) * cols + c + mc
                                b = (br + mr) * cols + bc + mc
                                msum += (image_data[a] - image_data[b]) ** 2
                        min_msum = min(msum, min_msum)

            out_data[r * cols + c] = min_msum

    return out


def _corner_fast(double[:, ::1] image, int n, double threshold):
    cdef int[:] rp = (np.round(3 * np.sin(2 * np.pi * np.arange(16, dtype=np.double) / 16))).astype(np.int32)
    cdef int[:] cp = (np.round(3 * np.cos(2 * np.pi * np.arange(16, dtype=np.double) / 16))).astype(np.int32)

    cdef Py_ssize_t rows = image.shape[0]
    cdef Py_ssize_t cols = image.shape[1]

    cdef Py_ssize_t i, j, k, l, m

    cdef char[:] bins = np.zeros(16, dtype=np.uint8)
    cdef int consecutive_count, speed_sum_b, speed_sum_d
    cdef int sp
    cdef double sum_b, sum_d, current_pixel
    cdef double[:, ::1] corner_response = np.zeros((rows, cols), dtype=np.double)

    cdef double circle_intensity

    for i in range(3, rows - 3):
        for j in range(3, cols - 3):

            current_pixel = image[i, j]
            speed_sum_b = 0
            speed_sum_d = 0
            sum_b = 0
            sum_d = 0

            for k in range(16):
                circle_intensity = image[i + rp[k], j + cp[k]]
                if circle_intensity > current_pixel + threshold:
                    # Brighter pixel
                    bins[k] = 'b'
                elif circle_intensity < current_pixel - threshold:
                    # Darker pixel
                    bins[k] = 'd'
                else:
                    # Similar pixel
                    bins[k] = 's'

            # High speed test for n>=12
            if n >= 12:
                for k in range(0, 16, 4):
                    if bins[k] == 'b':
                        speed_sum_b += 1
                    elif bins[k] == 'd':
                        speed_sum_d += 1
                if speed_sum_d < 3 and speed_sum_b < 3:
                    continue

            consecutive_count = 0
            for l in range(15 + n):
                if bins[l % 16] == 'b':
                    consecutive_count += 1
                    if consecutive_count == n:
                        for m in range(16):
                            if bins[m] == 'b':
                                sum_b += image[i + rp[m], j + cp[m]] - current_pixel - threshold
                            elif bins[m] == 'd':
                                sum_d += current_pixel - image[i + rp[m], j + cp[m]] - threshold
                        # Finding the response of the corner
                        if sum_d > sum_b:
                            corner_response[i, j] = sum_d
                        else:
                            corner_response[i, j] = sum_b
                        break
                else:
                    consecutive_count = 0

            if corner_response[i, j] == 0:
                consecutive_count = 0
                for l in range(15 + n):
                    if bins[l % 16] == 'd':
                        consecutive_count += 1
                        if consecutive_count == n:
                            for m in range(16):
                                if bins[m] == 'b':
                                    sum_b += image[i + rp[m], j + cp[m]] - current_pixel - threshold
                                elif bins[m] == 'd':
                                    sum_d += current_pixel - image[i + rp[m], j + cp[m]] - threshold
                            # Finding the response of the corner
                            if sum_d > sum_b:
                                corner_response[i, j] = sum_d
                            else:
                                corner_response[i, j] = sum_b
                            break
                    else:
                        consecutive_count = 0

    return np.asarray(corner_response)
