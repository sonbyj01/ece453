/*
* Henry Son
* ECE453 - Advanced Computer Architecture
* Professor Billoo
* 
* Header file for common metrics for image comparison
*
* Reference(s):
* https://en.wikipedia.org/wiki/Mean_squared_error
* https://en.wikipedia.org/wiki/Peak_signal-to-noise_ratio
*/

#ifndef __METRICS_H
#define __METRICS_H

#include <iostream>
#include <vector>

/* Mean Squared Error */
double _mse(std::vector<int>, 
            unsigned int, 
            unsigned int, 
            std::vector<int>);

/* Peak Signal-to-Noise Ratio */
double psnr(std::vector<int>, 
            unsigned int, 
            unsigned int,
            std::vector<int>);

#endif