-- Who Won That: dungeon book. Knows the bosses of the dungeons so the end of a run can be recognized by boss
-- fight ID, by boss name (when the client reports a fight ID of 0 or nothing) or by the creature that died.
-- Data comes from the dungeon book of the Podium addon, which is the reference for "when is a dungeon over".
local _, ns = ...

-- [dungeon] = { family (wings share it), last boss ("" = none: every boss must die), "boss:creature ID:fight IDs:o" ... }
-- a trailing "o" marks an optional boss (not needed for the end); a leading "?" on the last boss marks a guess.
local RAW = {
    ["alcaz prison"] = { "alcaz prison", "?blazeroar", "overseer wrex:255391:3403:;the questioner:256236:3415:;tidemistress cazass:255997:3410:;katerina the cleaner:257016:3418:;blazeroar:255702:3409:" },
    ["blackfathom deeps"] = { "blackfathom deeps", "akumai", "ghamoora:4887:219,2761,2916:;lady sarevess:4831:220,2762,2915:;gelihast:6243:221,2763,2914:;lorgus jett:12902:222:;old serrakis:4830:224,2765,2912:;twilight lord kelris:4832:225,2766,2911:;akumai:4829:226,2767,2910:" },
    ["blackmaw hold"] = { "blackmaw hold", "?varrox bleakhoof", "impaan the imprisoner:247206:3316:;bonesnout the unbroken:247198:3322:;moontouched wanderer:269104::o;gortek the apprentice:269111::o;tunnelweb matriarch:250034::o;withermaw:247195:3315:;elder shaman bloodmane:247209:3327:;blackmaw behemoth:247207:3323:;unbound spirit:247231:3336:;varrox bleakhoof:247234:3334:" },
    ["blackrock depths"] = { "blackrock depths", "emperor dagran thaurissan", "high interrogator gerstahn:9018:227:;lord roccor:9025:228:;houndmaster grebmar:9319:229:;gorosh the dervish:9027::;grizzle:9028::;eviscerator:9029::;okthor the breaker:9030::;anubshiah:9031::;hedrum the creeper:9032::;theldren:16059::o;pyromancer loregrain:9024:231:;fineous darkvire:9056:234:;warder stilgiss:9041:233:;lord incendius:9017:232:;baelgar:9016:235:;general angerforge:9033:236:;golem lord argelmach:8983:237:;hurley blackbreath:9537:238:;phalanx:9502:239:;ribbly screwspigot:9543:240:;plugger spazzring:9499:241:;ambassador flamelash:9156:242:;panzor the invincible:8923::o;the seven:9039:243:;magmus:9938:244:;princess moira bronzebeard:8929::o;emperor dagran thaurissan:9019:245:;ring of law::230:o" },
    ["city of dalaran"] = { "city of dalaran", "shade of the archmage", "atrexis the grave knight:247126:3311:;arcane anomaly:245999:3298:;fel ancient:246003:3299:;unstable sentinel:246017:3302:;mana devourer:246008:3300:;arcanic enigma:246016::;lyn the ignored:247032:3310:o;shade of the archmage:246020:3303:" },
    ["dire maul east"] = { "dire maul", "alzzin the wildshaper", "pusillin:14354::;zevrim thornhoof:11490:343:;hydrospawn:13280:344:;lethtendris:14327:345:;alzzin the wildshaper:11492:346:" },
    ["dire maul north"] = { "dire maul", "king gordok", "guard moldar:14326:362:;stomper kreeg:14322:363:;guard fengus:14321:364:;guard slipkik:14323:365:;captain kromcrush:14325:366:;chorush the observer:14324:367:;king gordok:11501:368:" },
    ["dire maul west"] = { "dire maul", "prince tortheldrin", "tendris warpwood:11489:350:;tsuzee:11467::o;magister kalendris:11487:348:;illyanna ravenoak:11488:347:;immolthar:11496:349:;lord helnurath:14506::o;prince tortheldrin:11486:361:" },
    ["excavation site wetlands"] = { "excavation site wetlands", "relic guardian", "saltspine:260322:3480:;shadetooth:260325:3481:;relic guardian:260326:3482:" },
    ["gnomeregan"] = { "gnomeregan", "mekgineer thermaplugg", "grubbis:7361:379:o;viscous fallout:7079:378:;electrocutioner:6235:380:;crowd pummeler:6229:381:;mekgineer thermaplugg:7800:382:;dark iron ambassador:6228::o" },
    ["hall of thanes"] = { "hall of thanes", "durgen dirgehammer", "faldrim anvilmar:261306:3493:;magmatus:::;plunder:261311:3494:;durgen dirgehammer:261319:3496:" },
    ["kroldok stronghold"] = { "kroldok stronghold", "?overlord mugg", "slavecrusher grox:258966:3450:;twilight commander zarmok:258972:3452:;war handler ashka:259281:3453:;nargurk:258964:3449:;bossman toof:264773::;kroog:262716::o;overlord mugg:258968:3451:" },
    ["lower blackrock spire"] = { "blackrock spire", "overlord wyrmthalak", "spirestone butcher:9219::o;spirestone battle lord:9218::o;spirestone lord magus:9217::o;highlord omokk:9196:267:;shadow hunter voshgajin:9236:268:;war master voone:9237:269:;mother smolderweb:10596:270:;crystal fang:10376::o;urok doomhowl:10584:271:;bannok grimaxe:9596::o;quartermaster zigris:9736:272:;halycon:10220:274:;gizrul the slavener:10268:273:;ghok bashguud:9718::o;overlord wyrmthalak:9568:275:" },
    ["maraudon"] = { "maraudon", "princess theradras", "noxxion:13282:422:;razorlash:12258:423:;lord vyletongue:12236:424:;meshlok the harvester:12237::o;celebras the cursed:12225:425:;landslide:12203:426:;tinkerer gizlock:13601:427:;rotgrip:13596:428:;princess theradras:12201:429:" },
    ["ragefire chasm"] = { "ragefire chasm", "", "oggleflint:11517:430,2732:;taragaman the hungerer:11520:431,2733:;jergosh the invoker:11518:432,2734:;bazzalan:11519:433,2735:" },
    ["razorfen downs"] = { "razorfen downs", "amnennar the coldbringer", "tutenkash:7355:434,2780:;plaguemaw the rotting:7356:2781:o;mordresh fire eye:7357:435,2782:;glutton:8567:436,2784:;ragglesnout:7354:2783:o;amnennar the coldbringer:7358:437,2785:" },
    ["razorfen kraul"] = { "razorfen kraul", "charlga razorflank", "roogug:6168:2773:;aggem thorncurse:4424:439,2774:;death speaker jargba:4428:440,2775:;overlord ramtusk:4420:441,2776:;agathelos the raging:4422:883,2777:;charlga razorflank:4421:443,2778:;blind hunter:4425::o;earthcaller halmgar:4842::o" },
    ["ruins of lordaeron"] = { "ruins of lordaeron", "rathmael", "the baron:250660::;witherfang:250483:3353:;the abandoned:250631:3357:o;bjork:256097:3412:;rathmael:250657:3354:;viktor the vile:256035:3411:o;lordaeron captain::3408:o" },
    ["scarlet monastery armory"] = { "scarlet monastery", "herod", "herod:3975:448:" },
    ["scarlet monastery cathedral"] = { "scarlet monastery", "high inquisitor whitemane", "high inquisitor fairbanks:4542:449:o;scarlet commander mograine:3976::;high inquisitor whitemane:3977:450:" },
    ["scarlet monastery graveyard"] = { "scarlet monastery", "bloodmage thalnos", "interrogator vishas:3983:444:;azshir the sleepless:6490::o;fallen champion:6488::o;ironspine:6489::o;bloodmage thalnos:4543:445:" },
    ["scarlet monastery library"] = { "scarlet monastery", "arcanist doan", "houndmaster loksey:3974:446:;arcanist doan:6487:447:" },
    ["scholomance"] = { "scholomance", "darkmaster gandling", "kirtonos the herald:10506::;jandice barov:10503::;rattlegore:11622::;marduk blackpool:10433::;vectus:10432::;ras frostwhisper:10508::;instructor malicia:10505::;doctor theolen krastinov:11261::;lorekeeper polkelt:10901::;the ravenian:10507::;lord alexei barov:10504::;lady illucia barov:10502::;darkmaster gandling:1853::" },
    ["shadowfang keep"] = { "shadowfang keep", "archmage arugal", "rethilgore:3914:464,2748:;fel steed:3864::o;shadow charger:3864::o;razorclaw the butcher:3886:465,2749:;baron silverlaine:3887:466,2750:;commander springvale:4278:467,2751:;odo the blindwatcher:4279:468,2752:;deathsworn captain:3872::o;arugals voidwalker:4627::;fenrus the devourer:4274:469,2753:;wolf master nandos:3927:470,2754:;archmage arugal:4275:471,2755:" },
    ["shapers terrace"] = { "shapers terrace", "?nanaya", "titanosaur:253201:3498:;venomridge:261813:3501:;thunderhoof:261812:3500:;direhorn matriarch:262127:3507:;cinder:261974:3503:;bolt:262081:3505:;snowtalon:262297:3597:;vitrix:272561:3600:;izharel and torrel:253218::;nanaya:261809:3502:" },
    ["stratholme living"] = { "stratholme", "balnazzar", "skul:10393::o;hearthsinger forresten:10558:473:o;the unforgiven:10516:472:;timmy the cruel:10808:474:;malor the zealous:11032:476:o;postmaster malown:11143:2798:o;cannon master willey:10997:475:;archivist galford:10811:477:;balnazzar:10813:478:" },
    ["stratholme undead"] = { "stratholme", "baron rivendare", "stonespine:10809::o;nerubenkan:10437:480:;baroness anastari:10436:479:;maleki the pallid:10438:481:;magistrate barthilas:10435:482:;ramstein the gorger:10439:483:;baron rivendare:10440:484:" },
    ["sunken temple"] = { "sunken temple", "shade of eranikus", "atalalarion:8580::;morphaz hazzas:5719:490,491:;jammalan the prophet:5710:488:;ogom the wretched:5711::;dreamscythe weaver:5721:486,487:;shade of eranikus:5709:493:;avatar of hakkar:8443:492:" },
    ["deadmines"] = { "deadmines", "edwin vancleef", "rhahkzor:644:161,2741:;miner johnson:3586::o;sneeds shredder:642::;sneed:643:162,2742:;gilnid:1763:163,2743:;mr smite:646:164,2745:;captain greenskin:647:166,2744:;edwin vancleef:639:167,2747:;cookie:645:165,2746:o" },
    ["drowned city"] = { "drowned city", "minloth the serpent", "zulalai:258905:3474:;vartaka:258924:3475:;captain dreadrise:260042:3476:;deathless marrow::3478:;gill:264177::o;umbra:264172::o;pyromancer braxton:260468::o;minloth the serpent:260274:3479:;primeval elemental::3511:o" },
    ["stockade"] = { "stockade", "", "targorr the dread:1696:2756:;kam deepfury:1666:2757:;hamhock:1717:2758:;dextren ward:1663:2759:;bazil thredd:1716:2760:;bruegal ironknuckle:1720::o" },
    ["uldaman"] = { "uldaman", "archaedas", "revelosh:6910:547:;the lost dwarves:6906:548:;ironaya:7228:549:;obsidian sentinel:7023::;ancient stone keeper:7206:551:;galgann firehammer:7291:552:;grimlok:4854:553:;archaedas:2748:554:" },
    ["upper blackrock spire"] = { "blackrock spire", "general drakkisath", "pyroguard emberseer:9816:276,3062:;solakar flamewreath:10264:277:;jed runewatcher:10509::o;goraluk anvilcrack:10899::;gyth:10339:3063:;warchief rend blackhand:10429:278:;the beast:10430:279,3068:;lord valthalak:16042:3070:o;general drakkisath:10363:280,3069:" },
    ["wailing caverns"] = { "wailing caverns", "mutanus the devourer", "lord cobrahn:3669:586:;lady anacondra:3671:585:;kresh:3653:587:;lord pythas:3670:588:;skum:3674:589:;lord serpentis:3673:590:;verdan the everliving:5775:591:;mutanus the devourer:3654:592:;deviate faerie dragon:5912::o" },
    ["zulfarrak"] = { "zulfarrak", "chief ukorz sandscalp", "theka the martyr:7272:596:;antusul:8127:595:;witch doctor zumrah:7271:597:;nekrum gutchewer:7796:598:;shadowpriest sezzziz:7275:599:;sergeant bly:7604::;hydromancer velratha:7795:593:;gahzrilla:7273:594:;zerillis:10082::o;sandarr dunereaver:10080::o;dustwraith:10081::o;ruuzlu:7797::;chief ukorz sandscalp:7267:600:" },
}

local function Simple(str)
    if type(str) ~= "string" or (issecretvalue and issecretvalue(str)) then
        return nil
    end
    return (str:lower():gsub("[^%a%s]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

local BY_ENCOUNTER, BY_CREATURE, FAMILIES, DUNGEONS = {}, {}, {}, {}
for key, raw in pairs(RAW) do
    local final = raw[2]:gsub("^%?", "")
    local dungeon = { key = key, family = raw[1], final = final ~= "" and final or nil, bosses = {} }
    for part in raw[3]:gmatch("[^;]+") do
        local name, creature, fights, optional = part:match("^([^:]*):([^:]*):([^:]*):([^:]*)$")
        if name then
            local boss = { name = name, optional = optional == "o" }
            for id in fights:gmatch("%d+") do
                BY_ENCOUNTER[tonumber(id)] = { dungeon, boss }
            end
            creature = tonumber(creature)
            if creature and not boss.optional then
                BY_CREATURE[creature] = BY_CREATURE[creature] or { dungeon, boss }
            end
            dungeon.bosses[#dungeon.bosses + 1] = boss
        end
    end
    DUNGEONS[key] = dungeon
    FAMILIES[dungeon.family] = FAMILIES[dungeon.family] or {}
    table.insert(FAMILIES[dungeon.family], key)
end

local ALIAS = { ["stormwind stockade"] = "stockade" }

-- The dungeons an instance can be: one, or the wings of one (Scarlet Monastery shares a single instance).
local function Candidates(instanceName)
    local name = Simple(instanceName)
    name = name and name:gsub("^the ", "")
    if not name then
        return {}
    end
    name = ALIAS[name] or name
    if DUNGEONS[name] then
        return { name }
    end
    if FAMILIES[name] then
        return FAMILIES[name]
    end
    for family, keys in pairs(FAMILIES) do
        if name:find(family, 1, true) == 1 then
            return keys
        end
    end
    return {}
end

-- Which dungeon and boss a kill was: by fight ID first, then by name among the dungeons of this instance.
local function Where(encounterID, name, instanceName)
    local hit = encounterID and BY_ENCOUNTER[encounterID]
    if hit then
        return hit[1], hit[2]
    end
    name = Simple(name)
    if not name then
        return nil
    end
    local foundDungeon, foundBoss
    for _, key in ipairs(Candidates(instanceName)) do
        for _, boss in ipairs(DUNGEONS[key].bosses) do
            if boss.name == name then
                if foundDungeon and foundDungeon ~= DUNGEONS[key] then
                    return nil -- the same boss name in two wings: cannot tell which
                end
                foundDungeon, foundBoss = DUNGEONS[key], boss
            end
        end
    end
    return foundDungeon, foundBoss
end

-- Notes a boss kill in the run and answers: true = this kill finishes the dungeon, false = it does not,
-- nil = the book does not know this kill (the caller falls back to its other checks).
local function EndedBy(run, encounterID, name)
    local dungeon, boss = Where(encounterID, name, run.name)
    if not (dungeon and boss) then
        return nil
    end
    run.killedBosses = run.killedBosses or {}
    run.killedBosses[boss] = true
    if dungeon.final and boss.name == dungeon.final then
        return true
    end
    local required = 0
    for _, b in ipairs(dungeon.bosses) do
        if not b.optional then
            required = required + 1
            if not run.killedBosses[b] then
                return false
            end
        end
    end
    return required > 0
end

local function WasKilled(run, boss)
    return run.killedBosses ~= nil and run.killedBosses[boss] == true
end

-- Boss for a creature ID (the kill event fires even when the fight events did not come).
local function BossOfCreature(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
        return nil
    end
    local id = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    local hit = id and BY_CREATURE[tonumber(id)]
    return hit and hit[2]
end

-- ===== shared with the other files =====
ns.DungeonBook = { EndedBy = EndedBy, WasKilled = WasKilled, BossOfCreature = BossOfCreature }
