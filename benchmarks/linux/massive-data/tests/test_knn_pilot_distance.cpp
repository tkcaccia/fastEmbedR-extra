#include "native_knn_cuda_pilot.h"

#include <cmath>
#include <limits>
#include <vector>

int main() {
  using fastembedr::query_pilot_distance_recall;
  const std::vector<float> tied{0.0f, 0.0f, 0.0f};
  const std::vector<float> same{0.0f, 0.0f, 0.0f};
  const std::vector<float> far{0.0f, 0.0f, 0.1f};
  const std::vector<float> near{0.0f, 0.0f, 0.000001f};
  const std::vector<float> invalid{
      0.0f, 0.0f, std::numeric_limits<float>::quiet_NaN()};
  if (query_pilot_distance_recall(tied, same, 1, 3) != 1.0) return 1;
  if (query_pilot_distance_recall(tied, far, 1, 3) != 2.0 / 3.0) {
    return 2;
  }
  if (query_pilot_distance_recall(tied, near, 1, 3) != 1.0) return 3;
  if (query_pilot_distance_recall(tied, invalid, 1, 3) !=
      2.0 / 3.0) return 4;
  const std::vector<float> normal{0.1f, 0.2f, 0.3f};
  const std::vector<float> omitted{0.1f, 0.2f, 0.4f};
  if (query_pilot_distance_recall(normal, omitted, 1, 3) !=
      2.0 / 3.0) return 5;
  return 0;
}
