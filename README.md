# RENAME LOW/HIGH BY PROXIMITY — 3D Max Script

Renames LOW and HIGH poly objects with matching `_low` / `_high` suffixes by pairing each LOW with its closest HIGH by bounding box center distance. Built to speed up baking prep in Marmoset, Substance Painter or any baker that matches by name.

---

## INSTALLATION

Drag the `.ms` file into the 3ds Max viewport, or go to `Scripting > Run Script`.

To keep it handy: `Customize > Customize User Interface > Toolbars` → find **Khanzino Tools** → drag **Rename LH** to a toolbar or create a new one.

---

## USAGE

**1. LOW objects** — Select your LOW objects, set a base name and press **Rename selected LOW bases + store**. They get renamed sequentially (`asset_001`, `asset_002`...) and stored automatically. If they're already named, select them and press **Store selected LOW objects** instead.

**2. HIGH objects** — Select your HIGH objects and press **Store selected HIGH objects**.

**3. Match and rename** — Press **Match pairs + add _low/_high**. Done. Matched pairs are selected in the viewport ready to bake. If anything is left unmatched, those objects are selected instead so you can spot them immediately.

---

## KNOWN LIMITATIONS

- Greedy 1:1 matching — each LOW gets one HIGH, no multi-shell support.
- Stored arrays are in memory only — closing the dialog or the scene clears them.
- One base name per batch pass.

---

## AUTHOR

Made by Oscar "Khanzino", environment & prop artist.  
I built this for my own pipeline and figured someone else might find it useful. No strings attached.

[ArtStation](https://www.artstation.com/khanzino) · [LinkedIn](https://www.linkedin.com/in/oscar-diaz-vento-181257204)

---

## LICENSE

Do whatever you want with it. MIT if you need something official.
