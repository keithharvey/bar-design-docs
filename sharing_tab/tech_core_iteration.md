So the creator of tech core is asking me (attean/keithharvey) to make changes to tech_core. We are currently working off of sharing_tab then back-porting to split out PRs, so any changes can be made on sharing_tab on either BYAR-Chobby or Beyond-All-Reason in ~/code

1. We need to reduce the cost of t2 labs whenever the Tech Blocking checkbox is enabled

New values:

```lua
    armalab = {
        energycost = 10000,
        metalcost = 1700,
        buildtime = 15000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
    coralab = {
        energycost = 10000,
        metalcost = 1700,
        buildtime = 15000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
    legalab = {
        energycost = 10000,
        metalcost = 1700,
        buildtime = 15000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
    armavp = {
        energycost = 10000,
        metalcost = 1850,
        buildtime = 16500,
        health = 3600,
        maxslope = 15,
        workertime = 200,
    },
    coravp = {
        energycost = 10000,
        metalcost = 1850,
        buildtime = 16500,
        health = 3600,
        maxslope = 15,
        workertime = 200,
    },
    legavp = {
        energycost = 10000,
        metalcost = 1850,
        buildtime = 16500,
        health = 3600,
        maxslope = 15,
        workertime = 200,
    },
    armaap = {
        energycost = 11000,
        metalcost = 2000,
        buildtime = 20000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
    coraap = {
        energycost = 11000,
        metalcost = 2000,
        buildtime = 20000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
    legaap = {
        energycost = 11000,
        metalcost = 2000,
        buildtime = 20000,
        health = 3500,
        maxslope = 15,
        workertime = 200,
    },
```
Hover text will need to be updated to note the reduction in price on the Tech Blocking checkbox.


2. We also want to copy the existing experimental "core printer" into a new unit that is producable by Keystone's with the following stats, but call it something other than core printer, we were thinking Voussoirs (and Springers for the t1.5 mex below) to keep with Keystone's masonry theme. 

```lua
    corprinter = {
        canmove = true,
        autoheal = 5,
        builddistance = 100,
        builder = true,
        buildtime = 10000,
        energycost = 6500,
        energymake = 20,
        energystorage = 50,
        metalcost = 350,
        health = 900,
        sightdistance = 430,
        movementclass = "HOVER3",
        speed = 55,
        leavetracks = false,
        workertime = 200,
        cantbetransported = true,
        buildoptions = {
        [1] = "legmext15",
        [2] = "false",
        [3] = "false",
        [4] = "false",
            },
            customparams = {
            techlevel = 1,
            unitgroup = "buildert1",
            },
    },
```

This unit can build one thing, a copied-in version of the t1.5 mex from legion, which we will call "Springers":

```lua
    legmext15 = {
        activatewhenbuilt = true,
        maxdec = 0,
        energycost = 5500,
        metalcost = 550,
        buildtime = 10000,
        energyupkeep = 30,
        extractsmetal = 0.003,
        health = 1800,
        metalstorage = 200,
        customparams = {
            metal_extractor = 1,
        },
        featuredefs = {
            dead = {
                damage = 500,
                metal = 300,
            },
            heap = {
                damage = 1000,
                metal = 150,
            },
        },
    },
```

Note that the keystone has no yardmap so it will need to produce units in the same "select blueprint and click" method as the armnanotct2.


```lua
armnanotct2 = {
        builder = true,
        builddistance = 50,
         workertime = 1,
        buildtime = 1,
        energycost = 1,
        health = 10,
        maxwaterdepth = 1000,
        metalcost = 1,
        cantbetransported = true,
          buildoptions = {
            "corprinter",
          },
        customparams = {
            unitgroup = 'builder',
            techlevel = 1,
        },
    },
```
Note that this wont be correct in terms of workertime and builddistance, workertime can be 200 and builddistance can be the shield distance