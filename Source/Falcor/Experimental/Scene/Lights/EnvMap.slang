/***************************************************************************
 # Copyright (c) 2020, NVIDIA CORPORATION. All rights reserved.
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
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
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
import Experimental.Scene.Lights.EnvMapData;
import Utils.Math.MathHelpers;
//import Utils.Color.ColorHelpers;

/** Struct for accessing an environment map.
*/
struct EnvMap
{
    Texture2D       envMap;         ///< Environment map texture.
    SamplerState    envSampler;     ///< Environment map sampler.

    EnvMapData      data;           ///< Environment map data.

    EnvMapData      prevData;

    /** Evaluates the radiance coming from world space direction 'dir'.
    */
    float3 eval(float3 dir, bool isLastFrame = false, float lod = 0.f)
    {
        // Get (u,v) coord in latitude-longitude map format.
        float2 uv = world_to_latlong_map(toLocal(dir, isLastFrame));
        return data.intensity * data.tint * envMap.SampleLevel(envSampler, uv, lod).rgb;
    }

    float3 evalLocal(float3 dir, float lod = 0.f)
    {
        // Get (u,v) coord in latitude-longitude map format.
        float2 uv = world_to_latlong_map(dir);
        return data.intensity * data.tint * envMap.SampleLevel(envSampler, uv, lod).rgb;
    }

    float3 evalUV(float uv, float lod = 0.f)
    {
        return data.intensity * data.tint * envMap.SampleLevel(envSampler, uv, lod).rgb;
    }

    /** Transform direction from local to world space.
    */
    float3 toWorld(float3 dir, bool isLastFrame = false)
    {
        // TODO: For identity transform we might want to skip this statically.
        if (isLastFrame) return mul(dir, (float3x3)prevData.transform);
        else return mul(dir, (float3x3)data.transform);
    }

    /** Transform direction from world to local space.
    */
    float3 toLocal(float3 dir, bool isLastFrame = false)
    {
        // TODO: For identity transform we might want to skip this statically.
        if (isLastFrame) return mul(dir, (float3x3)prevData.invTransform);
        else return mul(dir, (float3x3)data.invTransform);
    }

    float3 UVToWorld(float2 uv)
    {
        return toWorld(latlong_map_to_world(uv));
    }
};
