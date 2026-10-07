from pathlib import Path
import argparse, os, sys, math, tempfile
import cv2
import numpy as np
import onnxruntime as ort
from gradio_client import Client, handle_file
from PIL import Image, ImageCms

ROOT=Path(getattr(sys,"_MEIPASS",Path(__file__).resolve().parent))
cv2.setNumThreads(2)

SPACE="lllyasviel/IC-Light"

PROMPTS={
    "cinematic_warm":"cinematic warm portrait lighting, premium wedding photography, elegant amber highlights, soft dimensional shadows, realistic skin, luxurious atmosphere, natural photographic color",
    "luxury_indoor":"luxury indoor portrait lighting, warm practical ambience, polished editorial mood, soft directional key light, realistic skin and fabric, premium interior atmosphere",
    "golden_wedding":"golden hour wedding lighting, romantic warm glow, soft sunlit atmosphere, elegant highlights, realistic skin, premium cinematic wedding photography",
    "soft_romantic":"soft romantic portrait lighting, gentle luminous ambience, pastel warmth, delicate glow, natural skin, elegant wedding mood",
    "editorial_flash":"high-end editorial flash lighting, crisp dimensional subject light, controlled dark ambient background, luxury fashion photography, realistic skin and clothing",
    "moody_premium":"moody premium portrait lighting, deep elegant shadows, selective warm highlights, cinematic luxury atmosphere, realistic skin and fabric",
    "cool_blue_hour":"blue hour cinematic portrait lighting, refined cool ambience, subtle warm skin contrast, premium evening photography",
    "sunset_drama":"dramatic sunset lighting, warm orange side light, cinematic atmosphere, rich shadow depth, realistic skin and clothing",
    "filmic_wedding":"filmic wedding photography, cinematic color harmony, soft directional light, natural skin, rich but realistic atmosphere, premium analog-inspired mood",
    "dreamy_soft":"dreamy soft light, luminous wedding atmosphere, subtle bloom, gentle pastel warmth, realistic skin, elegant photographic mood"
}

NEGATIVE="different person, changed face, altered identity, changed hairstyle, changed pose, changed clothing, altered jewelry, deformed hands, extra fingers, warped anatomy, changed composition, lowres, blurry face, bad anatomy, bad hands, oversaturated skin, plastic skin, cartoon, illustration"

LIGHT_MAP={
    "left":"Left Light",
    "right":"Right Light",
    "top":"Top Light",
    "bottom":"Bottom Light",
    "ambient":"Left Light",
}

def ort_session(path):
    so=ort.SessionOptions()
    so.intra_op_num_threads=2
    so.inter_op_num_threads=1
    so.graph_optimization_level=ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(str(path),sess_options=so,providers=["CPUExecutionProvider"])

class MODNet:
    def __init__(self):
        self.session=ort_session(ROOT/"models"/"modnet_photographic.onnx")
        self.input=self.session.get_inputs()[0].name
        self.outputs=[x.name for x in self.session.get_outputs()]
    def predict(self,bgr):
        h,w=bgr.shape[:2]
        rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
        target=512
        if w>=h:
            nh=target; nw=max(32,int(w/h*target))
        else:
            nw=target; nh=max(32,int(h/w*target))
        nh-=nh%32; nw-=nw%32
        x=cv2.resize(rgb,(nw,nh),interpolation=cv2.INTER_AREA).astype(np.float32)/255.0
        x=(x-.5)/.5
        x=np.transpose(x,(2,0,1))[None]
        matte=self.session.run(self.outputs,{self.input:x})[0]
        matte=np.squeeze(matte).astype(np.float32,copy=False)
        matte=cv2.resize(matte,(w,h),interpolation=cv2.INTER_CUBIC).astype(np.float32,copy=False)
        matte=np.ascontiguousarray(np.clip(matte,0,1),dtype=np.float32)
        return cv2.GaussianBlur(matte,(0,0),1.1).astype(np.float32,copy=False)

class FaceDetector:
    def __init__(self):
        self.detector=None
        try:
            self.detector=cv2.FaceDetectorYN_create(
                str(ROOT/"models"/"face_detection_yunet_2023mar.onnx"),
                "",(320,320),0.72,0.3,5000
            )
        except Exception:
            self.detector=None
    def mask(self,bgr):
        h,w=bgr.shape[:2]
        mask=np.zeros((h,w),dtype=np.float32)
        if self.detector is None:
            return mask
        scale=min(1.0,1200.0/max(h,w))
        small=cv2.resize(bgr,(max(1,int(w*scale)),max(1,int(h*scale)))) if scale<1 else bgr
        sh,sw=small.shape[:2]
        try:
            self.detector.setInputSize((sw,sh))
            _,faces=self.detector.detect(small)
        except Exception:
            return mask
        if faces is None:
            return mask
        yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
        for f in faces:
            x,y,bw,bh=f[:4]/scale
            cx=x+bw*.5; cy=y+bh*.50
            rx=max(4,bw*.68); ry=max(4,bh*.84)
            e=1.0-(((xx-cx)/rx)**2+((yy-cy)/ry)**2)
            mask=np.maximum(mask,np.clip(e,0,1).astype(np.float32))
        return cv2.GaussianBlur(mask,(0,0),max(1.5,min(h,w)*.006)).astype(np.float32)

def read_image(path):
    data=np.fromfile(str(path),dtype=np.uint8)
    im=cv2.imdecode(data,cv2.IMREAD_COLOR)
    if im is None:
        raise ValueError("Cannot decode input")
    return im

def srgb_profile_bytes():
    try:
        return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    except Exception:
        return None

def write_image(path,im):
    p=Path(path); p.parent.mkdir(parents=True,exist_ok=True)
    rgb=cv2.cvtColor(im,cv2.COLOR_BGR2RGB)
    image=Image.fromarray(rgb)
    icc=srgb_profile_bytes()
    if p.suffix.lower() in (".tif",".tiff"):
        kw={"compression":"tiff_lzw"}
        if icc: kw["icc_profile"]=icc
        image.save(str(p),format="TIFF",**kw)
    else:
        kw={"quality":96,"subsampling":0}
        if icc: kw["icc_profile"]=icc
        image.save(str(p),format="JPEG",**kw)

def fit_generation_size(w,h):
    max_side=832
    scale=min(1.0,max_side/max(w,h))
    nw=max(512,int(round(w*scale/64))*64)
    nh=max(512,int(round(h*scale/64))*64)
    nw=min(nw,1024); nh=min(nh,1024)
    return nw,nh

def _extract_gallery_path(value):
    if isinstance(value, str):
        p=Path(value)
        if p.exists():
            return str(p)
        return None
    if isinstance(value, dict):
        for key in ("path","name","url"):
            v=value.get(key)
            if isinstance(v,str) and Path(v).exists():
                return v
        for v in value.values():
            p=_extract_gallery_path(v)
            if p:
                return p
        return None
    if isinstance(value,(list,tuple)):
        for v in value:
            p=_extract_gallery_path(v)
            if p:
                return p
    return None

def run_iclight(path,cfg):
    im=Image.open(path)
    w,h=im.size
    gw,gh=fit_generation_size(w,h)

    mode=cfg["mode"]
    mood=np.clip(cfg["moodStrength"]/100.0,0,1)
    prompt_inf=np.clip(cfg["promptInfluence"]/100.0,0,1)

    if mode=="safe":
        low_denoise=.48+.10*mood
        high_denoise=.20+.08*mood
        cfg_scale=1.7+0.5*prompt_inf
        steps=20
    elif mode=="strong":
        low_denoise=.70+.18*mood
        high_denoise=.34+.16*mood
        cfg_scale=2.2+0.8*prompt_inf
        steps=28
    else:
        low_denoise=.58+.14*mood
        high_denoise=.26+.10*mood
        cfg_scale=1.9+0.6*prompt_inf
        steps=24

    prompt=PROMPTS[cfg["preset"]]
    if cfg["lightSource"]=="ambient":
        prompt += ", balanced overall environmental illumination, coherent scene-wide light"
    else:
        prompt += ", coherent scene-wide illumination affecting subject and environment"

    client=Client(SPACE,verbose=False)
    result=client.predict(
        handle_file(path),
        prompt,
        int(gw),
        int(gh),
        1,
        12345,
        int(steps),
        "best quality, photorealistic, realistic texture, preserve subject identity and composition",
        NEGATIVE,
        float(cfg_scale),
        1.5,
        float(high_denoise),
        float(low_denoise),
        LIGHT_MAP[cfg["lightSource"]],
        api_name="/process_relight"
    )

    gallery=result[1] if isinstance(result,(list,tuple)) and len(result)>1 else result
    out_path=_extract_gallery_path(gallery)
    if not out_path:
        raise RuntimeError("Official IC-Light Space returned no image. The public queue may be busy or temporarily unavailable.")

    gen=cv2.imread(out_path,cv2.IMREAD_COLOR)
    if gen is None:
        data=np.fromfile(out_path,dtype=np.uint8)
        gen=cv2.imdecode(data,cv2.IMREAD_COLOR)
    if gen is None:
        raise ValueError("Cannot decode IC-Light output")
    return gen

def local_tone_map(orig,gen,alpha,face,cfg):
    h,w=orig.shape[:2]
    gen=cv2.resize(gen,(w,h),interpolation=cv2.INTER_CUBIC)
    o=orig.astype(np.float32)/255.0
    g=gen.astype(np.float32)/255.0

    sigma=max(10.0,min(h,w)*.030)
    o_low=cv2.GaussianBlur(o,(0,0),sigma).astype(np.float32)
    g_low=cv2.GaussianBlur(g,(0,0),sigma).astype(np.float32)

    # AI result is used only as a low-frequency illumination/color field.
    ratio=np.clip((g_low+.035)/(o_low+.035),.58,1.72).astype(np.float32)
    delta=np.clip(g_low-o_low,-.30,.30).astype(np.float32)

    mood=np.clip(cfg["moodStrength"]/100.0,0,1)
    original_light=np.clip(cfg["originalLight"]/100.0,0,1)
    strength=mood*(1.0-original_light*.72)

    if cfg["mode"]=="safe":
        strength*=.66
    elif cfg["mode"]=="strong":
        strength*=1.12

    relit=np.clip(o*(1.0+(ratio-1.0)*strength)+delta*(.30*strength),0,1)

    # Structure preservation keeps every original edge/detail. Since relit is derived
    # from original pixels, this control only limits the strength of the AI field.
    structure=np.clip(cfg["structurePreservation"]/100.0,0,1)
    relit=o*(structure*.32)+relit*(1.0-structure*.32)

    # Identity protection reduces chromatic/exposure change on the subject while still
    # allowing it to receive scene-consistent light.
    identity=np.clip(cfg["identityProtection"]/100.0,0,1)
    subj=np.clip(alpha,0,1)[...,None]
    subj_keep=identity*.52
    relit=relit*(1.0-subj*subj_keep)+o*(subj*subj_keep)

    # Face gets the strongest protection, but some illumination remains.
    face_prot=np.clip(cfg["faceProtection"]/100.0,0,1)
    fm=np.clip(face,0,1)[...,None]*(face_prot*.72)
    relit=relit*(1.0-fm)+o*fm

    # Preserve original high-frequency texture exactly.
    detail=o-o_low
    detail_weight=.88+.10*structure
    relit_low=cv2.GaussianBlur(relit.astype(np.float32),(0,0),sigma)
    out=np.clip(relit_low+detail*detail_weight,0,1)

    # Final mild highlight compression.
    lum=cv2.cvtColor((out*255).astype(np.uint8),cv2.COLOR_BGR2GRAY).astype(np.float32)/255.0
    hp=np.clip((lum-.90)/.10,0,1)[...,None]
    out=out*(1-.38*hp)+o*(.38*hp)

    return np.clip(out*255,0,255).astype(np.uint8)

def parse_row(parts):
    if len(parts)!=13:
        raise ValueError(f"Expected 13 manifest columns, got {len(parts)}")
    sid,inp,tif,jpg,mode,preset,light_source,mood,identity,structure,face,original,prompt=parts
    return sid,inp,tif,jpg,{
        "mode":mode,"preset":preset,"lightSource":light_source,
        "moodStrength":float(mood),"identityProtection":float(identity),
        "structurePreservation":float(structure),"faceProtection":float(face),
        "originalLight":float(original),"promptInfluence":float(prompt)
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--manifest",required=True)
    ap.add_argument("--results",required=True)
    a=ap.parse_args()

    lines=Path(a.manifest).read_text(encoding="utf-8").splitlines()
    if not lines or lines[0]!="ANAI_RELIGHT_V5_BATCH_1":
        raise ValueError("Unsupported V5 manifest")

    matte=MODNet()
    face_detector=FaceDetector()
    results=["ANAI_RELIGHT_V5_RESULTS_1"]
    hard_fail=False

    for line in lines[1:]:
        if not line.strip():
            continue
        sid="0"
        try:
            sid,inp,tif,jpg,cfg=parse_row(line.split("\t"))
            orig=read_image(inp)
            alpha=matte.predict(orig)
            face=face_detector.mask(orig)

            gen=run_iclight(inp,cfg)
            out=local_tone_map(orig,gen,alpha,face,cfg)

            write_image(tif,out)
            if jpg:
                write_image(jpg,out)

            results.append(f"{sid}\tok\tIC-Light mood transferred; original subject pixels/details protected")
        except Exception as e:
            hard_fail=True
            msg=str(e).replace("\t"," ").replace("\r"," ").replace("\n"," ")[:700]
            results.append(f"{sid}\terror\t{msg}")

    Path(a.results).write_text("\n".join(results)+"\n",encoding="utf-8")
    raise SystemExit(2 if hard_fail else 0)

if __name__=="__main__":
    main()
