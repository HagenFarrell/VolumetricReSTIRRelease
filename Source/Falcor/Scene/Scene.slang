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
#include "Scene/Material/MaterialDefines.slangh"
#include "Utils/HostDeviceShared.slangh"

__exported import Scene.SceneTypes;
__exported import Scene.Camera.Camera;
__exported import Scene.Lights.LightData;
__exported import Scene.Lights.LightProbeData;
__exported import Scene.Material.MaterialData;

import HitInfo;
import TextureSampler;
import Utils.Attributes;
import Experimental.Scene.Lights.LightCollection;
import Experimental.Scene.Lights.EnvMap;
import Experimental.Scene.Material.TexLODHelpers;
__exported import Scene.ParticleSystem.ParticleData;

struct PatchVertex2Data
{
    float4 position[2];
    float4 normal[2];
    // TODO: add normal if necessary
};

struct PatchVertex4Data
{
    float4 position[4];
    // TODO: add normal if necessary
};

#ifndef MATERIAL_COUNT
// This error occurs when a shader imports Scene.slang without setting the defines
// returned by Scene::getSceneDefines().
#error "MATERIAL_COUNT not defined!"
#endif

#ifndef PARTICLE_SYSTEM_COUNT
// This error occurs when a shader imports Scene.slang without setting the defines
// returned by Scene::getSceneDefines().
#error "PARTICLE_SYSTEM_COUNT not defined!"
#endif

/** Data required for rendering
*/
struct Scene
{
    // Geometry
    [root] StructuredBuffer<PackedMeshInstanceData> meshInstances;
    StructuredBuffer<MeshDesc> meshes;
    StructuredBuffer<CurveDesc> curves;
    VolumeDesc volumeDesc;
    StructuredBuffer<ParticleSystemDesc> particleSystems;
    StructuredBuffer<uint2> triangleInstanceMapping;

    [root] StructuredBuffer<float4> worldMatrices;
    [root] StructuredBuffer<float4> inverseTransposeWorldMatrices; // TODO: Make this 3x3 matrices (stored as 4x3). See #795.
    StructuredBuffer<float4> previousFrameWorldMatrices;

    [root] StructuredBuffer<PackedStaticVertexData> vertices;       ///< Vertex data for this frame.
    StructuredBuffer<PrevVertexData> prevVertices;                  ///< Vertex data for the previous frame, to handle skinned meshes.

#if INDEXED_VERTICES
    [root] ByteAddressBuffer indices;                               ///< Vertex indices, three 32-bit indices per triangle packed tightly.
#endif

    StructuredBuffer<CurveVertexData> curveVertices;

    StructuredBuffer<ParticleVertexData> particleVertices;
    ByteAddressBuffer particleIndices;

    // Materials
    StructuredBuffer<MaterialData> materials;
    MaterialResources materialResources[MATERIAL_COUNT];

    StructuredBuffer<Particle> particlePools[PARTICLE_SYSTEM_COUNT];

    // Volume rendering

    float3 volumeWorldTranslation = float3(0, 0, 0);
    float volumeWorldScaling = 1.f;
    float emissiveIntensityMultiplier = 1.f;
    float4x4 volumeExternalWorldToModelMatrix;
    float4x4 volumeExternalModelToWorldMatrix;

    // Lights and camera
    uint lightCount;
    StructuredBuffer<LightData> lights;
    LightCollection lightCollection;
    LightProbeData lightProbe;
    EnvMap envMap;
    Camera camera;
    uint numMeshInstances;
    uint numTriangleInstances;
    uint curveInstanceOffset; // numMeshInstances + numParticleSystems

    float surfaceGlobalAlphaMultipler;
    float particleCurveGlobalAlphaMultipler;

    float4x4 loadWorldMatrix(uint matrixID)
    {
        float4x4 m =
        {
            worldMatrices[matrixID * 4 + 0],
            worldMatrices[matrixID * 4 + 1],
            worldMatrices[matrixID * 4 + 2],
            worldMatrices[matrixID * 4 + 3]
        };
        return m;
    }

    float4x4 getWorldMatrix(uint meshInstanceID)
    {
        uint matrixID = meshInstances[meshInstanceID].unpack().globalMatrixID;
        return loadWorldMatrix(matrixID);
    };

    float3x3 loadInverseTransposeWorldMatrix(uint matrixID)
    {
        float3x3 m =
        {
            inverseTransposeWorldMatrices[matrixID * 4 + 0].xyz,
            inverseTransposeWorldMatrices[matrixID * 4 + 1].xyz,
            inverseTransposeWorldMatrices[matrixID * 4 + 2].xyz
        };
        return m;
    }

    float3x3 getInverseTransposeWorldMatrix(uint meshInstanceID)
    {
        uint matrixID = meshInstances[meshInstanceID].unpack().globalMatrixID;
        return loadInverseTransposeWorldMatrix(matrixID);
    };

    float4x4 getPrevWorldMatrix(uint meshInstanceID)
    {
        uint matrixID = meshInstances[meshInstanceID].unpack().globalMatrixID;

        float4x4 m =
        {
            previousFrameWorldMatrices[matrixID * 4 + 0],
            previousFrameWorldMatrices[matrixID * 4 + 1],
            previousFrameWorldMatrices[matrixID * 4 + 2],
            previousFrameWorldMatrices[matrixID * 4 + 3]
        };
        return m;
    };

    uint getMaterialID(uint meshInstanceID)
    {
        return meshInstances[meshInstanceID].materialID;
    };

    uint getParticleMaterialID(uint particleSystemID)
    {
        return particleSystems[particleSystemID].materialID;
    };

    uint getCurveMaterialID(uint curveID)
    {
        return curves[curveID].materialID;
    };

    uint getMaterialCount()
    {
        return MATERIAL_COUNT;
    }

    MaterialData getMaterial(uint materialID)
    {
        return materials[materialID];
    }

    MeshInstanceData getMeshInstance(uint meshInstanceID)
    {
        return meshInstances[meshInstanceID].unpack();
    }

    MeshDesc getMeshDesc(uint meshInstanceID)
    {
        return meshes[meshInstances[meshInstanceID].unpack().meshID];
    }

    CurveDesc getCurveDesc(uint curveInstanceID)
    {
        return curves[curveInstanceID];
    }

    uint2 uniformSampleTriangleInstance(float u)
    {
        int triangleInstanceId = min(numTriangleInstances-1, u * numTriangleInstances);
        return triangleInstanceMapping[triangleInstanceId];
    }

    uint2 getMeshInstanceIDandTriangleIDFromTriangleInstanceID(uint triangleInstanceId)
    {
        return triangleInstanceMapping[triangleInstanceId];
    }

    uint getLightCount()
    {
        return lightCount;
    }

    LightData getLight(uint lightIndex)
    {
        return lights[lightIndex];
    }

    bool isWorldMatrixFlippedWinding(uint meshInstanceID)
    {
        return (meshInstances[meshInstanceID].unpack().flags & uint(MeshInstanceFlags::Flipped)) != 0;
    }


    // Geometry access

    /** Returns the global vertex indices for a given triangle.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \return Vertex indices into the global vertex buffer.
    */
    uint3 getIndices(uint meshInstanceID, uint triangleIndex)
    {
#if INDEXED_VERTICES
        uint baseIndex = meshInstances[meshInstanceID].ibOffset + (triangleIndex * 3);
        uint3 vtxIndices = indices.Load3(baseIndex * 4);
#else
        uint baseIndex = triangleIndex * 3;
        uint3 vtxIndices = { baseIndex, baseIndex + 1, baseIndex + 2 };
#endif
        vtxIndices += meshInstances[meshInstanceID].vbOffset;
        return vtxIndices;
    }

    uint4 getCurveIndices(uint curveInstanceID, uint patchIndex)
    {
        CurveDesc desc = getCurveDesc(curveInstanceID);
        uint numVertsPerPatch = desc.getVerticesPerPatch();
        uint baseIndex = desc.vbOffset + numVertsPerPatch * patchIndex;
        return desc.curveType == 0 ? uint4(baseIndex, baseIndex + 1, baseIndex, baseIndex + 1) : uint4(baseIndex, baseIndex + 1, baseIndex + 2, baseIndex + 3);
    }

    uint3 getParticleIndices(uint particleSystemID, uint triangleIndex)
    {
        uint baseIndex = particleSystems[particleSystemID].ibOffset + (triangleIndex * 3);
        uint3 vtxIndices = particleIndices.Load3(baseIndex * 4);
        vtxIndices += particleSystems[particleSystemID].vbOffset;
        return vtxIndices;
    }

    /** Returns vertex data for a vertex.
        \param[in] index Global vertex index.
        \return Vertex data.
    */
    StaticVertexData getVertex(uint index)
    {
        return vertices[index].unpack();
    }

    ParticleVertexData getParticleVertex(uint index)
    {
        return particleVertices[index];
    }

    ParticleVertexData getParticleVertex(uint particleSystemID, uint billboardID)
    {
        return particleVertices[particleSystems[particleSystemID].vbOffset + billboardID];
    }

    /** Returns a triangle's face normal in object space.
        \param[in] vtxIndices Indices into the scene's global vertex buffer.
        \param[out] Face normal in object space (normalized). Front facing for counter-clockwise winding.
    */
    float3 getFaceNormalInObjectSpace(uint3 vtxIndices)
    {
        float3 p0 = vertices[vtxIndices[0]].position;
        float3 p1 = vertices[vtxIndices[1]].position;
        float3 p2 = vertices[vtxIndices[2]].position;
        return normalize(cross(p1 - p0, p2 - p0));
    }

    /** Returns a triangle's face normal in world space.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[out] Face normal in world space (normalized).
    */
    float3 getFaceNormalW(uint meshInstanceID, uint triangleIndex)
    {
        uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);
        float3 p0 = vertices[vtxIndices[0]].position;
        float3 p1 = vertices[vtxIndices[1]].position;
        float3 p2 = vertices[vtxIndices[2]].position;
        float3 N = cross(p1 - p0, p2 - p0);
        float3x3 worldInvTransposeMat = getInverseTransposeWorldMatrix(meshInstanceID);
        return normalize(mul(N, worldInvTransposeMat));
    }

    /** Returns a triangle's area in world space.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[out] Triangle area.
    */
    float getFaceAreaW(uint meshInstanceID, uint triangleIndex)
    {
        float3 p[3];
        getVertexPositionsW(meshInstanceID, triangleIndex, p);
        return 0.5f * length(cross(p[1] - p[0], p[2] - p[0]));
    }

    /** Computes the face normal and area of a triangle given its vertices.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] p Position of vertex 0,1,2 in world space.
        \param[out] triangleArea Triangle area in world space units.
        \return Face normal in world space (normalized).
    */
    float3 computeFaceNormalAndAreaW(uint meshInstanceID, const float3 p[3], out float triangleArea)
    {
        // Compute face normal in world space.
        // The length of the vector is twice the triangle area since we're in world space.
        // Note that this is not true if the normal is transformed using the inverse-transpose.
        float3 e[2];
        e[0] = p[1] - p[0];
        e[1] = p[2] - p[0];
        float3 N = cross(e[0], e[1]);
        triangleArea = 0.5f * length(N);

        // Flip the normal if the instance transform changed the handedness of the coordinate system.
        if (isWorldMatrixFlippedWinding(meshInstanceID)) N = -N;

        return normalize(N);
    }

    /** Returns a triangle's face normal and area in world space.
        This function should only be used if the triangle area is needed, as it is less efficient than computing just its normal.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[out] triangleArea Triangle area in world space units.
        \return Face normal in world space (normalized).
    */
    float3 getFaceNormalAndAreaW(uint meshInstanceID, uint triangleIndex, out float triangleArea)
    {
        uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);

        // Load vertices and transform to world space.
        float3 p[3];
        [unroll]
        for (int i = 0; i < 3; i++)
        {
            p[i] = vertices[vtxIndices[i]].position;
            p[i] = mul(float4(p[i], 1.f), getWorldMatrix(meshInstanceID)).xyz;
        }

        return computeFaceNormalAndAreaW(meshInstanceID, p, triangleArea);
    }

    /** Returns the interpolated vertex attributes for a given triangle.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] barycentrics Barycentric coordinates in the triangle.
        \param[out] Unpacked fetched vertices which can be used for further computations involving individual vertices.
        \return Interpolated vertex attributes.
    */
    VertexData getVertexData(uint meshInstanceID, uint triangleIndex, float3 barycentrics, out StaticVertexData vertices[3])
    {
        const uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);
        VertexData v = {};

        vertices = { gScene.getVertex(vtxIndices[0]), gScene.getVertex(vtxIndices[1]), gScene.getVertex(vtxIndices[2]) };

        v.posW += vertices[0].position * barycentrics[0];
        v.posW += vertices[1].position * barycentrics[1];
        v.posW += vertices[2].position * barycentrics[2];

        v.normalW += vertices[0].normal * barycentrics[0];
        v.normalW += vertices[1].normal * barycentrics[1];
        v.normalW += vertices[2].normal * barycentrics[2];

        v.tangentW += vertices[0].tangent * barycentrics[0];
        v.tangentW += vertices[1].tangent * barycentrics[1];
        v.tangentW += vertices[2].tangent * barycentrics[2];
        v.tangentW.w = sign(v.tangentW.w); // Preserve zero to indicate invalid tangent.

        v.texC += vertices[0].texCrd * barycentrics[0];
        v.texC += vertices[1].texCrd * barycentrics[1];
        v.texC += vertices[2].texCrd * barycentrics[2];

        v.faceNormalW = getFaceNormalInObjectSpace(vtxIndices);

        float4x4 worldMat = getWorldMatrix(meshInstanceID);
        float3x3 worldInvTransposeMat = getInverseTransposeWorldMatrix(meshInstanceID);

        v.posW = mul(float4(v.posW, 1.f), worldMat).xyz;
        v.normalW = mul(v.normalW, worldInvTransposeMat);
        v.faceNormalW = mul(v.faceNormalW, worldInvTransposeMat);
        v.tangentW.xyz = mul(v.tangentW.xyz, (float3x3)worldMat);

        v.normalW = normalize(v.normalW);
        v.faceNormalW = normalize(v.faceNormalW);
        // Handle invalid tangents gracefully (avoid NaN from normalization).
        v.tangentW.xyz = v.tangentW.w != 0.f ? normalize(v.tangentW.xyz) : float3(0, 0, 0);
        return v;
    }

    /** Returns the interpolated vertex attributes for a given triangle.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] barycentrics Barycentric coordinates in the triangle.
        \return Interpolated vertex attributes.
    */    

    VertexData getVertexData(uint meshInstanceID, uint triangleIndex, float3 barycentrics)
    {
        StaticVertexData vertices[3];
        return getVertexData(meshInstanceID, triangleIndex, barycentrics, vertices);
    }

    VertexData getVertexData(uint meshInstanceID, uint triangleIndex, float3 barycentrics, out float2 dzdxy)
    {
        StaticVertexData vertices[3];
        VertexData v = getVertexData(meshInstanceID, triangleIndex, barycentrics, vertices);

        float4 screen_p0 = mul(float4(vertices[0].position, 1), gScene.camera.getViewProj());
        float4 screen_p1 = mul(float4(vertices[1].position, 1), gScene.camera.getViewProj());
        float4 screen_p2 = mul(float4(vertices[2].position, 1), gScene.camera.getViewProj());
        screen_p0.xyz /= screen_p0.w;
        screen_p1.xyz /= screen_p1.w;
        screen_p2.xyz /= screen_p2.w;
        screen_p0.xy = float2(0.5*screen_p0.x + 0.5, -0.5*screen_p0.y + 0.5);
        screen_p1.xy = float2(0.5*screen_p1.x + 0.5, -0.5*screen_p1.y + 0.5);
        screen_p2.xy = float2(0.5*screen_p2.x + 0.5, -0.5*screen_p2.y + 0.5);

        float det = (screen_p0.x - screen_p2.x) * (screen_p1.y - screen_p2.y) - (screen_p0.y - screen_p2.y) * (screen_p1.x - screen_p2.x);
        
        float dzdx = ((screen_p1.y - screen_p2.y) * (screen_p0.z - screen_p2.z) - (screen_p0.y - screen_p2.y) * (screen_p1.z - screen_p2.z))/det;
        float dzdy = (-(screen_p1.x - screen_p2.x) * (screen_p0.z - screen_p2.z) + ( screen_p0.x - screen_p2.x )  * (screen_p1.z - screen_p2.z))/det;

        // screen space ([0,1]) derivative of screen space depth z
        dzdxy = float2(dzdx, dzdy);

        return v;
    }

#ifndef PROCEDURAL_PARTICLE
    float2 getParticleTexCoords(uint particleSystemID, uint triangleID, float3 barycentrics, out uint particlePoolIndex)
    {
        const uint3 vtxIndices = getParticleIndices(particleSystemID, triangleID);
        ParticleVertexData vertices[3] = { gScene.getParticleVertex(vtxIndices[0]), gScene.getParticleVertex(vtxIndices[1]), gScene.getParticleVertex(vtxIndices[2]) };
        float2 texC = float2(0,0);
        texC += vertices[0].texCrd * barycentrics[0];
        texC += vertices[1].texCrd * barycentrics[1];
        texC += vertices[2].texCrd * barycentrics[2];
        particlePoolIndex = vertices[0].particlePoolIndex;
        return texC;
    }
#endif

    uint getParticlePoolIndex(uint particleSystemID, uint triangleID)
    {
#ifdef PROCEDURAL_PARTICLE
        uint vtxIdx0 = particleSystems[particleSystemID].vbOffset + triangleID;
#else
        uint baseIndex = particleSystems[particleSystemID].ibOffset + (triangleID * 3);
        uint vtxIdx0 = particleIndices.Load(baseIndex * 4);
        vtxIdx0 += particleSystems[particleSystemID].vbOffset;
#endif
        return gScene.getParticleVertex(vtxIdx0).particlePoolIndex;
    }

    OutParticleVertexData getParticleVertexData(uint particleSystemID, uint triangleIndex, float3 barycentrics, float3 rayOrigin, float3 rayDir)
    {
#ifdef PROCEDURAL_PARTICLE
        ParticleVertexData vertex = gScene.getParticleVertex(particleSystemID, triangleIndex);
        OutParticleVertexData v = {};

        float3 yAxis = float3(0,1,0);
        float3 nzAxis = float3(0,0,-1);
        float3 V = -rayDir;//normalize(rayOrigin - vertex.position);
        
        float3 bbX_ = abs(dot(rayDir, yAxis)) < 0.001 ? normalize(cross(nzAxis, V)) : normalize(cross(yAxis, V));
        float3 bbY_ = normalize(cross(V, bbX_));
        float3 bbX = vertex.scale * (cos(vertex.rotation) * bbX_ - sin(vertex.rotation) * bbY_);
        float3 bbY = vertex.scale * (sin(vertex.rotation) * bbX_ + cos(vertex.rotation) * bbY_);
        v.posW = vertex.position + (2*barycentrics.y-1) * bbX + (2*barycentrics.z-1) * bbY;

        // float4 viewPos = mul(float4(vertex.position, 1.f), camera.getView());
        // float2 rotOffset = vectorRotate(2*barycentrics.yz-1, sin(vertex.rotation), cos(vertex.rotation));
        // viewPos.xy += rotOffset * vertex.scale;
        // v.posW = mul(float4(viewPos.xyz,1), camera.data.invViewMat).xyz;

        v.texC = float2(barycentrics.y, 1 - barycentrics.z);
        v.particlePoolIndex = vertex.particlePoolIndex;
        v.normalW = camera.data.invViewMat[2].xyz;
#else
        const uint3 vtxIndices = getParticleIndices(particleSystemID, triangleIndex);
        OutParticleVertexData v = {};
        ParticleVertexData vertices[3] = { gScene.getParticleVertex(vtxIndices[0]), gScene.getParticleVertex(vtxIndices[1]), gScene.getParticleVertex(vtxIndices[2]) };
        v.posW += vertices[0].position * barycentrics[0];
        v.posW += vertices[1].position * barycentrics[1];
        v.posW += vertices[2].position * barycentrics[2];
        v.texC += vertices[0].texCrd * barycentrics[0];
        v.texC += vertices[1].texCrd * barycentrics[1];
        v.texC += vertices[2].texCrd * barycentrics[2];

        float3 p0 = vertices[0].position;
        float3 p1 = vertices[1].position;
        float3 p2 = vertices[2].position;
        v.normalW = normalize(cross(p1 - p0, p2 - p0));
        v.particlePoolIndex = vertices[0].particlePoolIndex;
#endif
        return v;
    }

    OutParticleVertexData getParticleVertexDataRayCones(uint particleSystemID, uint triangleIndex, float3 barycentrics, float3 rayOrigin, float3 rayDir)
    {
#ifdef PROCEDURAL_PARTICLE
        ParticleVertexData vertex = gScene.getParticleVertex(particleSystemID, triangleIndex);
        OutParticleVertexData v = {};

        float3 yAxis = float3(0,1,0);
        float3 nzAxis = float3(0,0,-1);
        float3 V = -rayDir;

        float3 bbX_ = abs(dot(rayDir, yAxis)) < 0.001 ? normalize(cross(nzAxis, V)) : normalize(cross(yAxis, V));
        float3 bbY_ = normalize(cross(V, bbX_));
        float3 bbX = vertex.scale * (cos(vertex.rotation) * bbX_ - sin(vertex.rotation) * bbY_);
        float3 bbY = vertex.scale * (sin(vertex.rotation) * bbX_ + cos(vertex.rotation) * bbY_);
        v.posW = vertex.position + (2*barycentrics.y-1) * bbX + (2*barycentrics.z-1) * bbY;

        v.texC = float2(barycentrics.y, 1 - barycentrics.z);
        v.particlePoolIndex = vertex.particlePoolIndex;
        v.normalW = camera.data.invViewMat[2].xyz;
        v.coneTexLODValue = computeRayConeBillboardLODValue(vertex.scale);
#else
        const uint3 vtxIndices = getParticleIndices(particleSystemID, triangleIndex);
        OutParticleVertexData v = {};
        float2 txcoords[3];
        float3 positions[3];
        txcoords[0] = particleVertices[vtxIndices[0]].texCrd;
        txcoords[1] = particleVertices[vtxIndices[1]].texCrd;
        txcoords[2] = particleVertices[vtxIndices[2]].texCrd;
        positions[0] = particleVertices[vtxIndices[0]].position;
        positions[1] = particleVertices[vtxIndices[1]].position;
        positions[2] = particleVertices[vtxIndices[2]].position;

        v.posW += positions[0] * barycentrics[0];
        v.posW += positions[1] * barycentrics[1];
        v.posW += positions[2] * barycentrics[2];
        v.texC += txcoords[0] * barycentrics[0];
        v.texC += txcoords[1] * barycentrics[1];
        v.texC += txcoords[2] * barycentrics[2];
        v.normalW = normalize(cross(positions[1] - positions[0], positions[2] - positions[0]));
        v.coneTexLODValue = computeRayConeTriangleLODValue(positions, txcoords, float3x3(1,0,0,0,1,0,0,0,1));
        v.particlePoolIndex = particleVertices[vtxIndices[0]].particlePoolIndex;
#endif
        return v;
    }

    OutCurveVertexData getCurveVertexData(uint curveID, uint triangleID, float3 barycentrics, float3 rayOrigin)
    {
        PatchVertex2Data patch = gScene.getCurveVertex2Data(curveID, triangleID/2);

        float3 edgeDir0 = cross(normalize(rayOrigin - patch.position[0].xyz), patch.normal[0].xyz);
        float3 edgeDir1 = cross(normalize(rayOrigin - patch.position[1].xyz), patch.normal[1].xyz);

        /**
        0     2
        -------
        |    /|  ^ edgeDir
        |  /  |  > tangent
        |/    |  . view
        -------
        1     3
        */
        float thickness0 = 0.5 * patch.position[0].w;
        float thickness1 = 0.5 * patch.position[1].w;

        float3 v[4];
        v[0] = patch.position[0].xyz + thickness0 * edgeDir0;
        v[1] = patch.position[0].xyz - thickness0 * edgeDir0;
        v[2] = patch.position[1].xyz + thickness1 * edgeDir1;
        v[3] = patch.position[1].xyz - thickness1 * edgeDir1;

        OutCurveVertexData outVertex;

        if (triangleID % 2 == 0)
        {
            float uHit = barycentrics[2];
            outVertex.tangentW = 0.5 * normalize(patch.normal[0].xyz * (1 - uHit) + patch.normal[1].xyz * uHit) + 0.5;
            outVertex.posW = barycentrics[0] * v[0] + barycentrics[1] * v[1] + barycentrics[2] * v[2];
        }
        else
        {
            float uHit = barycentrics[0] + barycentrics[2];
            outVertex.tangentW = 0.5 * normalize(patch.normal[0].xyz * (1 - uHit) + patch.normal[1].xyz * uHit) + 0.5;
            outVertex.posW = barycentrics[0] * v[2] + barycentrics[1] * v[1] + barycentrics[2] * v[3];
        }

        return outVertex;
    }

    /** Returns the interpolated vertex attributes for a given hitpoint.
        \param[in] hit Hit info.
        \return Interpolated vertex attributes.
    */
    VertexData getVertexData(HitInfo hit)
    {
        return getVertexData(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights());
    }

    VertexData getVertexDataRayCones(HitInfo hit)
    {
        return getVertexDataRayCones(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights());
    }

    OutParticleVertexData getParticleVertexData(HitInfo hit, float3 rayOrigin, float3 rayDir)
    {
        return getParticleVertexData(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights(), rayOrigin, rayDir);
    }

    OutParticleVertexData getParticleVertexDataRayCones(HitInfo hit, float3 rayOrigin, float3 rayDir)
    {
        return getParticleVertexDataRayCones(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights(), rayOrigin, rayDir);
    }

    OutCurveVertexData getCurveVertexData(HitInfo hit, float3 rayOrigin)
    {
        return getCurveVertexData(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights(), rayOrigin);
    }

    /** Returns interpolated vertex attributes in a ray tracing hit program when ray cones are used for texture LOD.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] barycentrics Barycentric coordinates in the triangle.
        \return Interpolated vertex attributes.
    */
    VertexData getVertexData(HitInfo hit, out StaticVertexData vertices[3])
    {
        return getVertexData(hit.meshInstanceID, hit.primitiveIndex, hit.getBarycentricWeights(), vertices);
    }

    /** Returns interpolated vertex attributes in a ray tracing hit program when ray cones are used for texture LOD.
       \param[in] meshInstanceID The mesh instance ID.
       \param[in] triangleIndex Index of the triangle in the given mesh.
       \param[in] barycentrics Barycentric coordinates in the triangle.
       \return Interpolated vertex attributes.
   */
    VertexData getVertexDataRayCones(uint meshInstanceID, uint triangleIndex, float3 barycentrics)
    {
        StaticVertexData triangleVertices[3];
        VertexData v = getVertexData(meshInstanceID, triangleIndex, barycentrics, triangleVertices);
        v.coneTexLODValue = computeRayConeTriangleLODValue(triangleVertices, meshInstanceID, float3x3(getWorldMatrix(meshInstanceID)));
        return v;
    }

    VertexData getVertexDataRayCones(uint meshInstanceID, uint triangleIndex, float3 barycentrics, out float2 dzdxy)
    {
        StaticVertexData triangleVertices[3];
        VertexData v = getVertexData(meshInstanceID, triangleIndex, barycentrics, triangleVertices);
        v.coneTexLODValue = computeRayConeTriangleLODValue(triangleVertices, meshInstanceID, float3x3(getWorldMatrix(meshInstanceID)));

        float4 screen_p0 = mul(float4(triangleVertices[0].position, 1), gScene.camera.getViewProj());
        float4 screen_p1 = mul(float4(triangleVertices[1].position, 1), gScene.camera.getViewProj());
        float4 screen_p2 = mul(float4(triangleVertices[2].position, 1), gScene.camera.getViewProj());
        screen_p0.xyz /= screen_p0.w;
        screen_p1.xyz /= screen_p1.w;
        screen_p2.xyz /= screen_p2.w;
        screen_p0.xy = float2(0.5*screen_p0.x + 0.5, -0.5*screen_p0.y + 0.5);
        screen_p1.xy = float2(0.5*screen_p1.x + 0.5, -0.5*screen_p1.y + 0.5);
        screen_p2.xy = float2(0.5*screen_p2.x + 0.5, -0.5*screen_p2.y + 0.5);

        float det = (screen_p0.x - screen_p2.x) * (screen_p1.y - screen_p2.y) - (screen_p0.y - screen_p2.y) * (screen_p1.x - screen_p2.x);
        
        float dzdx = ((screen_p1.y - screen_p2.y) * (screen_p0.z - screen_p2.z) - (screen_p0.y - screen_p2.y) * (screen_p1.z - screen_p2.z))/det;
        float dzdy = (-(screen_p1.x - screen_p2.x) * (screen_p0.z - screen_p2.z) + ( screen_p0.x - screen_p2.x )  * (screen_p1.z - screen_p2.z))/det;

        // screen space ([0,1]) derivative of screen space depth z
        dzdxy = float2(dzdx, dzdy);

        return v;
    }

    PatchVertex2Data getCurveVertex2Data(uint curveInstanceID, uint patchIndex)
    {
        PatchVertex2Data v = {};
        uint baseIndex = getCurveDesc(curveInstanceID).vbOffset + 2 * patchIndex;

        [unroll]
        for (int i = 0; i < 2; i++)
        {
            v.position[i] = curveVertices[baseIndex + i].position;
            v.normal[i] = curveVertices[baseIndex + i].normal;
        }

        return v;
    }

    PatchVertex4Data getCurveVertex4Data(uint curveInstanceID, uint patchIndex)
    {
        PatchVertex4Data v = {};
        uint baseIndex = getCurveDesc(curveInstanceID).vbOffset + 4 * patchIndex;

        [unroll]
        for (int i = 0; i < 4; i++)
        {
            v.position[i] = curveVertices[baseIndex+i].position;
        }

        return v;
    }

    /** Returns interpolated position on a triangle in world space for the previous frame.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] barycentrics Barycentric coordinates in the triangle.
        \return Interpolated position in world space for the previous frame.
    */
    float3 getPrevPosW(uint meshInstanceID, uint triangleIndex, float3 barycentrics)
    {
        const uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);
        float3 prevPos = float3(0, 0, 0);

        [unroll]
        for (int i = 0; i < 3; i++)
        {
            prevPos += prevVertices[vtxIndices[i]].position * barycentrics[i];
        }

        float4x4 prevWorldMat = getPrevWorldMatrix(meshInstanceID);
        return mul(float4(prevPos, 1.f), prevWorldMat).xyz;
    }

    /** Returns a triangle's vertex positions in world space.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[out] p Position of vertex 0,1,2 in world space.
    */
    void getVertexPositionsW(uint meshInstanceID, uint triangleIndex, out float3 p[3])
    {
        uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);
        float4x4 worldMat = getWorldMatrix(meshInstanceID);

        [unroll]
        for (int i = 0; i < 3; i++)
        {
            p[i] = vertices[vtxIndices[i]].position;
            p[i] = mul(float4(p[i], 1.f), worldMat).xyz;
        }
    }

    /** Returns a triangle's texture coordinates.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[out] texC Texture coordinate of vertex 0,1,2.
    */
    void getVertexTexCoords(uint meshInstanceID, uint triangleIndex, out float2 texC[3])
    {
        uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);

        [unroll]
        for (int i = 0; i < 3; i++)
        {
            texC[i] = vertices[vtxIndices[i]].texCrd;
        }
    }

    // Emissive access

    /** Check if a material has an emissive texture.
        \param[in] materialID Material ID
        \return Returns true if material has emissive texture.
    */
    bool isEmissiveTextured(uint materialID)
    {
        return EXTRACT_EMISSIVE_TYPE(materials[materialID].flags) == ChannelTypeTexture;
    }

    /** Evaluates the outgoing radiance on a given material.
        This function samples the emissive texture if its textured.
        Note the caller check the facing status themselves to discard back-facing hits.
        \param[in] materialID Material ID
        \param[in] uv Texture coordinates
        \param[in] mr MaterialResources struct for the given material ID. This is a workaround to avoid perf problems due to dynamic indexing.
        \return Evaluated outgoing radiance on the front-facing side.
    */
    float3 getEmissive(uint materialID, float2 uv, MaterialResources mr)
    {
        MaterialData m = materials[materialID];
        ExplicitLodTextureSampler lod = { 0.0 };
        return sampleTexture(mr.emissive, mr.samplerState, uv, float4(m.emissive, 1.0), EXTRACT_EMISSIVE_TYPE(m.flags), lod).rgb * m.emissiveFactor;
    }

    /** Returns the estimated curvature from a triangle vertex attributes for ray tracing using the provided estimator.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] curvatureEstimator Generic triangle curvature estimator to use.
        \return Estimated curvature.
    */
    float computeCurvatureGeneric<TCE : ITriangleCurvatureEstimator>(uint meshInstanceID, uint triangleIndex, TCE curvatureEstimator)
    {
        const uint3 vtxIndices = getIndices(meshInstanceID, triangleIndex);
        StaticVertexData vertices[3] = { getVertex(vtxIndices[0]), getVertex(vtxIndices[1]), getVertex(vtxIndices[2]) };
        float3 normals[3];
        float3 pos[3];
        normals[0] = vertices[0].normal;
        normals[1] = vertices[1].normal;
        normals[2] = vertices[2].normal;
        pos[0] = vertices[0].position;
        pos[1] = vertices[1].position;
        pos[2] = vertices[2].position;
        float3 edge01 = pos[1] - pos[0];
        float3 edge02 = pos[2] - pos[0];
        float3 edge12 = pos[2] - pos[1];
        float curvature01 = dot(normals[1] - normals[0], edge01) / dot(edge01, edge01);
        float curvature02 = dot(normals[2] - normals[0], edge02) / dot(edge02, edge02);
        float curvature12 = dot(normals[2] - normals[1], edge12) / dot(edge12, edge12);

        return curvatureEstimator.eval(edge01, edge02, edge12, curvature01, curvature02, curvature12);
    }

    /** Returns the estimated isoctropic curvature from vertex attributes for ray tracing.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \return Estimated curvature.
    */
    float computeCurvatureIsotropic(uint meshInstanceID, uint triangleIndex)
    {
        TriangleCurvature_Average tce = { };
        //TriangleCurvature_Max tce = { };          // Over-estimates curvature using max of the 3 edges.
        return computeCurvatureGeneric(meshInstanceID, triangleIndex, tce);
    }

    /** Returns the estimated visible curvature from vertex attributes for ray tracing using the ellipse intersection of a cone with the surface.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \return Estimated curvature.
    */
    float computeCurvatureVisibleEllipse(uint meshInstanceID, uint triangleIndex, float3 rayDir, float rayConeWidth, float rayConeAngle)
    {
        TriangleCurvature_EllipseVis tce = { rayDir, rayConeWidth, rayConeAngle };
        return computeCurvatureGeneric(meshInstanceID, triangleIndex, tce);
    }

    /** Returns the estimated isoctropic curvature from vertex attributes for ray tracing at the first hit point.
        \param[in] meshInstanceID The mesh instance ID.
        \param[in] triangleIndex Index of the triangle in the given mesh.
        \param[in] rayDir Ray direction.
        \return Estimated curvature.
    */
    float computeCurvatureIsotropicFirstHit(uint meshInstanceID, uint triangleIndex, float3 rayDir)
    {
        TriangleCurvature_DirClosestDP tce = { rayDir };
        return computeCurvatureGeneric(meshInstanceID, triangleIndex, tce);
    }
};

ParameterBlock<Scene> gScene;
