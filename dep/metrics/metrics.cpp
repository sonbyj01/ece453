/*
* Henry Son
* ECE453 - Advanced Computer Architecture
* Professor Billoo
* 
* Common metrics for image comparison
*
* Reference(s):
* https://en.wikipedia.org/wiki/Mean_squared_error
* https://en.wikipedia.org/wiki/Peak_signal-to-noise_ratio
*/

#include "metrics.h"
#include <iostream>
#include <cmath>
#include <limits>

/* Mean Squared Error */
double _mse(std::vector<int> img, unsigned int img_w, unsigned int img_h, std::vector<int> ref) {
    if(img.size() != ref.size()) {
        std::cerr << "Image sizes are not the same. Cannot calculate MSE." << std::endl;
        exit(-1);
    }

    double sq_err = 0;
    
    for(unsigned long i = 0; i < img.size(); i += 3) {
        /* RGB values for both the image img and reference ref */
        double img_rgb_r = img[i];
        double img_rgb_g = img[i + 1];
        double img_rgb_b = img[i + 2];
        
        double ref_rgb_r = ref[i];
        double ref_rgb_g = ref[i + 1];
        double ref_rgb_b = ref[i + 2];

        /* Calculate square error for each RGB value */
        double sq_err_r = pow((img_rgb_r - ref_rgb_r), 2);
        double sq_err_g = pow((img_rgb_g - ref_rgb_g), 2);
        double sq_err_b = pow((img_rgb_b - ref_rgb_b), 2);

        /* Append to total square error */
        sq_err += sq_err_r + sq_err_g + sq_err_b;
    }

    return sq_err / (img_w * img_h);
}

/* Peak Signal-to-Noise Ratio */
double psnr(std::vector<int> img, unsigned int img_w, unsigned int img_h, std::vector<int> ref) {
    if(img.size() != ref.size()) {
        std::cerr << "Image sizes are not the same. Cannot calculate pSNR." << std::endl;
        exit(-1);
    }

    /* Find MSE */
    double mean_sq_err = _mse(img, img_w, img_h, ref);

    /* Calculate pSNR */
    double R = 255;
    return 10 * log10(pow(R, 2) / mean_sq_err);
}