/***************************************************************************
 # Copyright (c) 2019, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/

 /** Temporal accumulation render pass.

     There are entry points for each of the three supported accumulation modes.
     Note that for the compensated summation mode the shader _must_ be compiled
     for precise floating-point operations (no reordering).

     In all modes, the shader writes the current accumulated average to the
     output texture. The intermediate buffers are internal to the pass.
 */

#include "Utils/Math/MathConstants.slangh"
__exported import Reservoir;
#include "HostDeviceSharedDefinitions.h"

cbuffer CB
{
    uint2   gResolution;
}

StructuredBuffer<Reservoir> gCurReservoirs;
RWStructuredBuffer<Reservoir> gTemporalReservoirs;
StructuredBuffer<ExtraBounceReservoir> gCurExtraBounceReservoirs;
RWStructuredBuffer<ExtraBounceReservoir> gTemporalExtraBounceReservoirs;

int decodeMaxIndirectBounces(int storage)
{
#if MAX_BOUNCES == 1
    return 0;
#else
    return storage >> 20;
#endif
}

inline int getPixelID(int2 pixelPos, int2 resolution)
{
    return pixelPos.y * resolution.x + pixelPos.x;
}

bool IsWithinRange(int2 pos, int2 resolution)
{
    return pos.x >= 0 && pos.x < resolution.x && pos.y >= 0 && pos.y < resolution.y;
}


#if MAX_BOUNCES > 1
void writeExtraBounceReservoirs(in Reservoir output)
{
    int maxIndirectBounces = decodeMaxIndirectBounces(output.sampledPixel);
    for (int bounceId = 0; bounceId < maxIndirectBounces; bounceId++)
    {
        gTemporalExtraBounceReservoirs[output.extraBounceStartId + bounceId] = gCurExtraBounceReservoirs[output.extraBounceStartId + bounceId];
    }
}
#endif

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    const int2 pixelPos = DTid.xy;
    if (!IsWithinRange(pixelPos, gResolution)) return;
    int pixelId = getPixelID(pixelPos, gResolution);
    Reservoir r = gCurReservoirs[pixelId];
    gTemporalReservoirs[pixelId] = r;
    #if MAX_BOUNCES > 1
    writeExtraBounceReservoirs(r);
    #endif
}
