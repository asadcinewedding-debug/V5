local Binding=import 'LrBinding'
local Dialogs=import 'LrDialogs'
local Export=import 'LrExportSession'
local Files=import 'LrFileUtils'
local Path=import 'LrPathUtils'
local Progress=import 'LrProgressScope'
local Tasks=import 'LrTasks'
local UUID=import 'LrUUID'
local View=import 'LrView'
local Engine=require 'Engine'

local M={}

local PRESETS={
    cinematic_warm=true,luxury_indoor=true,golden_wedding=true,
    soft_romantic=true,editorial_flash=true,moody_premium=true,
    cool_blue_hour=true,sunset_drama=true,filmic_wedding=true,
    dreamy_soft=true
}

local LIGHTS={left=true,right=true,top=true,bottom=true,ambient=true}

local function number(v,lo,hi,label)
    local n=tonumber(v)
    if not n or n~=n or n<lo or n>hi then
        error(label..' must be between '..lo..' and '..hi)
    end
    return n
end

function M.configure(ctx,count,prefs)
    local p=Binding.makePropertyTable(ctx)
    local f=View.osFactory()

    p.mode='balanced'
    p.preset='cinematic_warm'
    p.lightSource='left'
    p.moodStrength=62
    p.identityProtection=95
    p.structurePreservation=92
    p.faceProtection=95
    p.originalLight=20
    p.promptInfluence=55
    p.saveToken=false
    p.token=prefs.replicateToken or ''
    p.stack=true
    p.jpeg=false
    p.quality='high'

    local content=f:column{
        bind_to_object=p,
        spacing=f:control_spacing(),

        f:static_text{title='AN AI RELIGHT V5 — GENERATIVE MOOD RELIGHT',font='<system/bold>',width_in_chars=84},
        f:static_text{title='Subject unchanged • AI-generated lighting mood • Light + color focus',width_in_chars=84},

        f:group_box{
            title='1  GENERATIVE MODE',
            f:column{
                spacing=f:control_spacing(),
                f:row{
                    f:static_text{title='Mode',width_in_chars=24},
                    f:popup_menu{
                        value=View.bind('mode'),width_in_chars=34,
                        items={
                            {title='Safe Mood — maximum preservation',value='safe'},
                            {title='Balanced Creative — recommended',value='balanced'},
                            {title='Strong Mood — stronger atmosphere',value='strong'},
                        }
                    }
                },
                f:row{
                    f:static_text{title='Mood Preset',width_in_chars=24},
                    f:popup_menu{
                        value=View.bind('preset'),width_in_chars=34,
                        items={
                            {title='Cinematic Warm',value='cinematic_warm'},
                            {title='Luxury Indoor',value='luxury_indoor'},
                            {title='Golden Wedding',value='golden_wedding'},
                            {title='Soft Romantic',value='soft_romantic'},
                            {title='Editorial Flash',value='editorial_flash'},
                            {title='Moody Premium',value='moody_premium'},
                            {title='Cool Blue Hour',value='cool_blue_hour'},
                            {title='Sunset Drama',value='sunset_drama'},
                            {title='Filmic Wedding',value='filmic_wedding'},
                            {title='Dreamy Soft Light',value='dreamy_soft'},
                        }
                    }
                },
                f:row{
                    f:static_text{title='Virtual Light Direction',width_in_chars=24},
                    f:popup_menu{
                        value=View.bind('lightSource'),width_in_chars=26,
                        items={
                            {title='Left Light',value='left'},
                            {title='Right Light',value='right'},
                            {title='Top Light',value='top'},
                            {title='Bottom Light',value='bottom'},
                            {title='Ambient / Overall',value='ambient'},
                        }
                    }
                }
            }
        },

        f:group_box{
            title='2  AI MOOD CONTROLS',
            f:column{
                spacing=f:control_spacing(),
                f:row{
                    f:static_text{title='AI Mood Strength',width_in_chars=24},
                    f:edit_field{value=View.bind('moodStrength'),width_in_chars=8},
                    f:static_text{title='0–100'}
                },
                f:row{
                    f:static_text{title='Prompt Influence',width_in_chars=24},
                    f:edit_field{value=View.bind('promptInfluence'),width_in_chars=8},
                    f:static_text{title='0–100'}
                },
                f:row{
                    f:static_text{title='Original Light Retained',width_in_chars=24},
                    f:edit_field{value=View.bind('originalLight'),width_in_chars=8},
                    f:static_text{title='0–100'}
                },
            }
        },

        f:group_box{
            title='3  SUBJECT LOCK — DO NOT REDESIGN SUBJECT',
            f:column{
                spacing=f:control_spacing(),
                f:row{
                    f:static_text{title='Identity Protection',width_in_chars=24},
                    f:edit_field{value=View.bind('identityProtection'),width_in_chars=8},
                    f:static_text{title='Recommended 90–100'}
                },
                f:row{
                    f:static_text{title='Structure Preservation',width_in_chars=24},
                    f:edit_field{value=View.bind('structurePreservation'),width_in_chars=8},
                    f:static_text{title='Recommended 85–100'}
                },
                f:row{
                    f:static_text{title='Face Protection',width_in_chars=24},
                    f:edit_field{value=View.bind('faceProtection'),width_in_chars=8},
                    f:static_text{title='Recommended 90–100'}
                },
                f:static_text{
                    title='V5 uses the generated image only as a lighting/color reference. Fine subject detail is taken from the original image.',
                    width_in_chars=80,height_in_lines=2
                }
            }
        },

        f:group_box{
            title='4  GENERATIVE SERVICE',
            f:column{
                spacing=f:control_spacing(),
                f:static_text{title='Replicate API token (required for IC-Light generative relighting)',width_in_chars=78},
                f:edit_field{value=View.bind('token'),width_in_chars=70},
                f:checkbox{title='Save token in Lightroom plug-in preferences on this computer',value=View.bind('saveToken')},
                f:static_text{title='Token is never written to the V5 report. If not saved, it is used only for this operation.',width_in_chars=78},
            }
        },

        f:group_box{
            title='5  OUTPUT',
            f:column{
                spacing=f:control_spacing(),
                f:row{
                    f:static_text{title='Quality',width_in_chars=24},
                    f:popup_menu{
                        value=View.bind('quality'),width_in_chars=30,
                        items={
                            {title='High — 3072 px protected output',value='high'},
                            {title='Standard — 2048 px protected output',value='standard'}
                        }
                    }
                },
                f:checkbox{title='Import and stack relit TIFF above original',value=View.bind('stack')},
                f:checkbox{title='Also save JPEG preview',value=View.bind('jpeg')},
                f:static_text{title=count..' selected still photo(s). Internet is required for the generative pass.',width_in_chars=78}
            }
        }
    }

    if Dialogs.presentModalDialog{
        title='AN AI Relight V5 — Generative Mood',
        contents=content,
        actionVerb='Generate V5 Mood'
    }~='ok' then return nil end

    assert(p.mode=='safe' or p.mode=='balanced' or p.mode=='strong','Invalid V5 mode')
    assert(PRESETS[p.preset],'Invalid mood preset')
    assert(LIGHTS[p.lightSource],'Invalid light source')
    assert(p.quality=='high' or p.quality=='standard','Invalid quality')

    local token=tostring(p.token or ''):gsub('^%s+',''):gsub('%s+$','')
    assert(#token>10,'A Replicate API token is required for V5 generative relighting.')

    if p.saveToken then
        prefs.replicateToken=token
    elseif prefs.replicateToken then
        prefs.replicateToken=nil
    end

    return {
        mode=p.mode,preset=p.preset,lightSource=p.lightSource,
        moodStrength=number(p.moodStrength,0,100,'AI mood strength'),
        identityProtection=number(p.identityProtection,0,100,'Identity protection'),
        structurePreservation=number(p.structurePreservation,0,100,'Structure preservation'),
        faceProtection=number(p.faceProtection,0,100,'Face protection'),
        originalLight=number(p.originalLight,0,100,'Original light retained'),
        promptInfluence=number(p.promptInfluence,0,100,'Prompt influence'),
        token=token,stack=p.stack,jpeg=p.jpeg,quality=p.quality
    }
end

local function preflight()
    local exe=Path.child(_PLUGIN.path,Engine.executable())
    assert(Files.exists(exe),'AN AI Relight V5 engine is missing. Run the V5 installer again.')
    return exe
end

local function safeStem(photo)
    local name=photo:getFormattedMetadata('fileName') or 'photo'
    local stem=name:gsub('%.[^%.]+$',''):gsub('[<>:"/\\|%?%*]','_')
    return stem~='' and stem or 'photo'
end

local function uniqueOutput(photo,suffix)
    local src=photo:getRawMetadata('path')
    assert(type(src)=='string' and src~='','Cannot determine source photo path.')
    local dir=Path.parent(src)
    local base=safeStem(photo)..'-ANAI-Relight-V5'
    local out=Path.child(dir,base..suffix)
    local n=2
    while Files.exists(out) do
        out=Path.child(dir,base..'-'..n..suffix)
        n=n+1
    end
    return out
end

local function renderSource(photo,dir,progress,quality)
    local maxEdge=quality=='high' and 3072 or 2048
    local session=Export{photosToExport={photo},exportSettings={
        LR_exportServiceProvider='com.adobe.ag.export.file',
        LR_export_destinationType='specificFolder',
        LR_export_destinationPathPrefix=dir,
        LR_export_useSubfolder=false,
        LR_collisionHandling='rename',
        LR_format='JPEG',
        LR_jpeg_quality=1,
        LR_export_colorSpace='sRGB',
        LR_size_doConstrain=true,
        LR_size_doNotEnlarge=true,
        LR_size_resizeType='longEdge',
        LR_size_maxWidth=maxEdge,
        LR_size_maxHeight=maxEdge,
        LR_size_units='pixels',
        LR_outputSharpeningOn=false,
        LR_useWatermark=false,
        LR_reimportExportedPhoto=false,
        LR_renamingTokensOn=false,
        LR_minimizeEmbeddedMetadata=true,
        LR_removeLocationMetadata=true
    }}
    local rendered
    for _,rendition in session:renditions{stopIfCanceled=true,progressScope=progress} do
        local ok,path=rendition:waitForRender()
        assert(ok,'V5 source render failed: '..tostring(path))
        rendered=path
    end
    assert(rendered,'Lightroom returned no V5 source render.')
    return rendered
end

function M.run(ctx,catalog,photos,skipped,config,prefs,write)
    local engineExe=preflight()
    local root=Path.child(Path.getStandardFilePath('temp'),'ANAI-Relight-V5-'..UUID.generateUUID())
    assert(Files.createAllDirectories(root),'Cannot create V5 temporary folder.')

    local progress=Progress{title='AN AI Relight V5 - Generative Mood',functionContext=ctx}
    progress:setCancelable(true)
    ctx:addCleanupHandler(function() progress:done();Files.delete(root) end)

    local manifestPath=Path.child(root,'manifest.tsv')
    local tokenPath=Path.child(root,'token.txt')
    local resultsPath=Path.child(root,'results.tsv')
    local logPath=Path.child(root,'engine.log')

    local tf=assert(io.open(tokenPath,'wb'))
    tf:write(config.token)
    tf:close()

    local mf=assert(io.open(manifestPath,'wb'))
    mf:write('ANAI_RELIGHT_V5_BATCH_1\n')

    local outputById,sourceById={},{}
    local prepared,prepFailed=0,{}

    for i,photo in ipairs(photos) do
        if progress:isCanceled() then break end
        progress:setCaption('Preparing '..i..' / '..#photos..' - '..(photo:getFormattedMetadata('fileName') or 'Photo'))
        local dir=Path.child(root,tostring(i))
        Files.createAllDirectories(dir)

        local ok,err=Tasks.pcall(function()
            local input=renderSource(photo,dir,progress,config.quality)
            local tif=uniqueOutput(photo,'.tif')
            local jpg=config.jpeg and uniqueOutput(photo,'.jpg') or ''
            outputById[i]=tif
            sourceById[i]=photo

            local row={
                i,input,tif,jpg,
                config.mode,config.preset,config.lightSource,
                config.moodStrength,config.identityProtection,
                config.structurePreservation,config.faceProtection,
                config.originalLight,config.promptInfluence
            }
            mf:write(table.concat(row,'\t')..'\n')
            prepared=prepared+1
        end)

        if not ok then
            prepFailed[#prepFailed+1]=(photo:getFormattedMetadata('fileName') or ('Photo '..i))..': '..tostring(err)
        end
        progress:setPortionComplete(i,#photos*2)
        Tasks.yield()
    end

    mf:close()
    if progress:isCanceled() then progress:done();return end
    assert(prepared>0,'No photos could be prepared for V5.')

    progress:setCaption('V5: generating AI lighting mood and protecting original subject...')
    local command=Engine.quote(engineExe)..
        ' --manifest '..Engine.quote(manifestPath)..
        ' --results '..Engine.quote(resultsPath)..
        ' --token-file '..Engine.quote(tokenPath)..
        ' > '..Engine.quote(logPath)..' 2>&1'

    local status=Tasks.execute(Engine.wrap(command))
    Files.delete(tokenPath)

    assert(Files.exists(resultsPath),'V5 engine did not return results.\n'..(Files.readFile(logPath) or ''))

    local rows={}
    for line in (Files.readFile(resultsPath) or ''):gmatch('[^\r\n]+') do
        if line~='ANAI_RELIGHT_V5_RESULTS_1' then
            local id,state,message=line:match('^(%d+)\t(%a+)\t(.*)$')
            id=tonumber(id)
            if id and sourceById[id] then rows[id]={state=state,message=message} end
        end
    end

    local imported,failed=0,#prepFailed
    local report={
        'AN AI Relight V5 — Generative Mood',
        os.date('%Y-%m-%d %H:%M:%S'),
        'Mode: '..config.mode..' | Preset: '..config.preset..
        ' | Mood: '..config.moodStrength..
        ' | Identity protection: '..config.identityProtection..
        ' | Structure preservation: '..config.structurePreservation
    }

    for _,s in ipairs(prepFailed) do report[#report+1]='PREP ERROR - '..s end

    for i,photo in ipairs(photos) do
        local row=rows[i]
        if row and row.state=='ok' and Files.exists(outputById[i]) then
            local ok,err=Tasks.pcall(function()
                write(catalog,'AN AI Relight V5 - Import',function()
                    if config.stack then
                        catalog:addPhoto(outputById[i],photo,'above')
                    else
                        catalog:addPhoto(outputById[i])
                    end
                end)
            end)
            if ok then
                imported=imported+1
                report[#report+1]=(photo:getFormattedMetadata('fileName') or ('Photo '..i))..': OK - '..row.message
            else
                failed=failed+1
                report[#report+1]=(photo:getFormattedMetadata('fileName') or ('Photo '..i))..': IMPORT ERROR - '..tostring(err)
            end
        elseif outputById[i] then
            failed=failed+1
            report[#report+1]=(photo:getFormattedMetadata('fileName') or ('Photo '..i))..': ERROR - '..(row and row.message or 'Missing engine result')
        end
        progress:setPortionComplete(#photos+i,#photos*2)
        Tasks.yield()
    end

    progress:done()
    report[#report+1]='Rendered/imported: '..imported
    report[#report+1]='Failed: '..failed
    report[#report+1]='Skipped videos: '..skipped
    prefs.lastV5RelightReport=table.concat(report,'\n')
    Dialogs.message('AN AI Relight V5',prefs.lastV5RelightReport,'info')
end

return M
