//
//  NuoMeshTexMatieraled.m
//  ModelViewer
//
//  Created by dfeng on 9/7/16.
//  Copyright © 2016 middleware. All rights reserved.
//

#import "NuoMeshTexMatieraled.h"
#import "NuoTextureBase.h"


@implementation NuoMeshTexMatieraled
{
    id<MTLTexture> _textureOpacity;
    id<MTLTexture> _textureBump;
    BOOL _ignoreTextureAlpha;
    BOOL _physicallyReflection;
    
    NuoMeshModeShaderParameter _meshMode;
}


- (instancetype)initWithCommandQueue:(id<MTLCommandQueue>)commandQueue
                  withVerticesBuffer:(void*)buffer withLength:(size_t)length
                         withIndices:(void*)indices withLength:(size_t)indicesLength
{
    self = [super initWithCommandQueue:commandQueue
                    withVerticesBuffer:buffer
                            withLength:length
                           withIndices:indices
                            withLength:indicesLength];
    
    _meshMode = kMeshMode_Normal;
    
    return self;
}


- (instancetype)cloneForMode:(NuoMeshModeShaderParameter)mode
{
    NuoMeshTexMatieraled* texMaterialMesh = [NuoMeshTexMatieraled new];
    [texMaterialMesh shareResourcesFrom:self];
    
    texMaterialMesh->_meshMode = mode;
    
    [texMaterialMesh makePipelineShadowState];
    [texMaterialMesh makePipelineState:[texMaterialMesh makePipelineStateDescriptor]];
    [texMaterialMesh makeDepthStencilState];
    
    return texMaterialMesh;
}


- (void)shareResourcesFrom:(NuoMesh*)mesh
{
    NuoMeshTexMatieraled* meshTextured = (NuoMeshTexMatieraled*)mesh;
    
    [super shareResourcesFrom:mesh];
    _textureBump = meshTextured->_textureBump;
    _textureOpacity = meshTextured->_textureOpacity;
}



- (void)makeTextureOpacity:(NSString*)texPath withCommandQueue:(id<MTLCommandQueue>)queue
{
    NuoTextureBase* textureBase = [NuoTextureBase getInstance:queue];
    NuoTexture* texture = [textureBase texture2DWithImageNamed:texPath mipmapped:YES
                                             checkTransparency:NO];
    _textureOpacity = texture.texture;
}



- (void)makeTextureBump:(NSString*)texPath withCommandQueue:(id<MTLCommandQueue>)queue
{
    NuoTextureBase* textureBase = [NuoTextureBase getInstance:queue];
    NuoTexture* texture = [textureBase texture2DWithImageNamed:texPath mipmapped:YES
                                             checkTransparency:NO];
    _textureBump = texture.texture;
}


- (void)makePipelineScreenSpaceState
{
    [self makePipelineScreenSpaceStateWithVertexShader:_textureBump ? @"vertex_screen_space_tex_materialed_bump"
                                                                    : @"vertex_screen_space_tex_materialed"
                                    withFragemtnShader:@"fragement_screen_space_textured"];
}


- (void)makePipelineShadowState
{
    NSString* shadowShader = _textureBump ? @"vertex_shadow_tex_materialed_bump" : @"vertex_shadow_tex_materialed";
    [super makePipelineShadowState:shadowShader];
}



- (void)setIgnoreTexutreAlpha:(BOOL)ignoreAlpha
{
    _ignoreTextureAlpha = ignoreAlpha;
}



- (void)setPhysicallyReflection:(BOOL)physically
{
    _physicallyReflection = physically;
}



- (MTLRenderPipelineDescriptor*)makePipelineStateDescriptor
{
    id<MTLLibrary> library = [self.device newDefaultLibrary];
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipelineDescriptor.sampleCount = self.sampleCount;
    
    bool alphaInbedded = !_ignoreTextureAlpha;
    bool hasTexOpacity = !(!_textureOpacity);
    MTLFunctionConstantValues* funcConstant = [MTLFunctionConstantValues new];
    
    BOOL pcss = self.shadowOptionPCSS;
    BOOL pcf = self.shadowOptionPCF;
    
    [funcConstant setConstantValue:&alphaInbedded type:MTLDataTypeBool atIndex:0];
    [funcConstant setConstantValue:&hasTexOpacity type:MTLDataTypeBool atIndex:1];
    [funcConstant setConstantValue:&_physicallyReflection type:MTLDataTypeBool atIndex:2];
    [funcConstant setConstantValue:&pcss type:MTLDataTypeBool atIndex:4];
    [funcConstant setConstantValue:&pcf type:MTLDataTypeBool atIndex:5];
    [funcConstant setConstantValue:&_meshMode type:MTLDataTypeInt atIndex:6];
    
    if (!_textureBump)
    {
        pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertex_project_tex_materialed"];
        pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragment_light_tex_materialed"
                                                            constantValues:funcConstant
                                                                     error:nil];
    }
    else
    {
        pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertex_tex_materialed_tangent"];
        pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragment_tex_materialed_bump"
                                                            constantValues:funcConstant
                                                                     error:nil];
    }
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    MTLRenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDescriptor.colorAttachments[0];
    colorAttachment.blendingEnabled = YES;
    colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
    colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    unsigned int offset = 0;
    unsigned int attrIndex = 0;
    
    MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor new];
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat4;      // position
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat4;      // normal
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    if (_textureBump)
    {
        vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat4;  // tangent
        vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
        vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
        vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat4;  // bi-tangent
        vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
        vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    }
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat2;      // texCoord
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat3;      // diffuse
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat3;      // ambient
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat3;      // specular
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    vertexDescriptor.attributes[attrIndex].format = MTLVertexFormatFloat2;      // shinessDisolve
    vertexDescriptor.attributes[attrIndex].offset = offset; offset += 16;
    vertexDescriptor.attributes[attrIndex].bufferIndex = 0; ++attrIndex;
    
    vertexDescriptor.layouts[0].stride = offset;
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    
    return pipelineDescriptor;
}


- (void)drawScreenSpace:(id<MTLRenderCommandEncoder>)renderPass indexBuffer:(NSInteger)index
{
    [renderPass setFragmentTexture:self.diffuseTex atIndex:0];
    [renderPass setFragmentSamplerState:self.samplerState atIndex:0];
    
    [super drawScreenSpace:renderPass indexBuffer:index];
}


- (void)setSampleCount:(NSUInteger)sampleCount
{
    [super setSampleCount:sampleCount];
}


- (void)drawMesh:(id<MTLRenderCommandEncoder>)renderPass indexBuffer:(NSInteger)index
{
    [renderPass setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderPass setRenderPipelineState:self.renderPipelineState];
    [renderPass setDepthStencilState:self.depthStencilState];
    
    [renderPass setVertexBuffer:self.vertexBuffer offset:0 atIndex:0];
    [renderPass setVertexBuffer:self.transformBuffers[index] offset:0 atIndex:3];
    [renderPass setFragmentSamplerState:self.samplerState atIndex:1];
    
    NSUInteger texBufferIndex = 2; /* mesh texture starts after the shadow-map texture */
    
    [renderPass setFragmentTexture:self.diffuseTex atIndex:texBufferIndex++];
    if (_textureOpacity)
        [renderPass setFragmentTexture:_textureOpacity atIndex:texBufferIndex];
    
    ++texBufferIndex;
    if (_textureBump)
        [renderPass setFragmentTexture:_textureBump atIndex:texBufferIndex];
    
    [renderPass drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                           indexCount:[self.indexBuffer length] / sizeof(uint32_t)
                            indexType:MTLIndexTypeUInt32
                          indexBuffer:self.indexBuffer
                    indexBufferOffset:0];
}


- (BOOL)hasUnifiedMaterial
{
    if (_textureOpacity)
        return NO;

    if (_ignoreTextureAlpha)
        return [super hasUnifiedMaterial];
    
    if ([self hasTextureTransparency])
        return NO;
    
    return [super hasUnifiedMaterial];
}




@end






@implementation NuoMeshMatieraled
{
    BOOL _hasTransparent;
    BOOL _physicallyReflection;
    NuoMeshModeShaderParameter _meshMode;
}



- (instancetype)initWithCommandQueue:(id<MTLCommandQueue>)commandQueue
                  withVerticesBuffer:(void*)buffer withLength:(size_t)length
                         withIndices:(void*)indices withLength:(size_t)indicesLength
{
    self = [super initWithCommandQueue:commandQueue
                    withVerticesBuffer:buffer
                            withLength:length
                           withIndices:indices
                      withLength:indicesLength];
    
    if (self)
        _meshMode = kMeshMode_Normal;
    
    return self;
}



- (instancetype)cloneForMode:(NuoMeshModeShaderParameter)mode
{
    NuoMeshMatieraled* materialMesh = [NuoMeshMatieraled new];
    [materialMesh shareResourcesFrom:self];
    
    materialMesh->_meshMode = mode;
    
    [materialMesh makePipelineShadowState];
    [materialMesh makePipelineState:[materialMesh makePipelineStateDescriptor]];
    [materialMesh makeDepthStencilState];
    
    return materialMesh;
}


- (void)makePipelineScreenSpaceState
{
    return [self makePipelineScreenSpaceStateWithVertexShader:@"vertex_screen_space_materialed"
                                           withFragemtnShader:@"fragement_screen_space"];
}


- (void)makePipelineShadowState
{
    [super makePipelineShadowState:@"vertex_shadow_materialed"];
}



- (MTLRenderPipelineDescriptor*)makePipelineStateDescriptor
{
    id<MTLLibrary> library = [self.device newDefaultLibrary];
    
    BOOL pcss = self.shadowOptionPCSS;
    BOOL pcf = self.shadowOptionPCF;
    
    MTLFunctionConstantValues* funcConstant = [MTLFunctionConstantValues new];
    [funcConstant setConstantValue:&_physicallyReflection type:MTLDataTypeBool atIndex:2];
    [funcConstant setConstantValue:&pcss type:MTLDataTypeBool atIndex:4];
    [funcConstant setConstantValue:&pcf type:MTLDataTypeBool atIndex:5];
    [funcConstant setConstantValue:&_meshMode type:MTLDataTypeInt atIndex:6];
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertex_project_materialed"];
    pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragment_light_materialed"
                                                        constantValues:funcConstant error:nil];
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    pipelineDescriptor.sampleCount = self.sampleCount;
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    MTLRenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDescriptor.colorAttachments[0];
    colorAttachment.blendingEnabled = YES;
    colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
    colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
    colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor new];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[1].offset = 16;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[2].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[2].offset = 32;
    vertexDescriptor.attributes[2].bufferIndex = 0;
    vertexDescriptor.attributes[3].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[3].offset = 48;
    vertexDescriptor.attributes[3].bufferIndex = 0;
    vertexDescriptor.attributes[4].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[4].offset = 64;
    vertexDescriptor.attributes[4].bufferIndex = 0;
    vertexDescriptor.attributes[5].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[5].offset = 80;
    vertexDescriptor.attributes[5].bufferIndex = 0;
    
    vertexDescriptor.layouts[0].stride = 96;
    vertexDescriptor.layouts[0].stepRate = 1;
    vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    
    pipelineDescriptor.vertexDescriptor = vertexDescriptor;
    
    return pipelineDescriptor;
}



- (BOOL)hasTransparency
{
    return _hasTransparent;
}



- (void)setTransparency:(BOOL)transparent
{
    _hasTransparent = transparent;
}


- (void)setPhysicallyReflection:(BOOL)physically
{
    _physicallyReflection = physically;
}



@end


