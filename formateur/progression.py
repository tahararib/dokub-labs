#!/usr/bin/env python3
"""Grille de progression DOKUB, à partir du chat de la session.

Copiez le chat (tout, sans trier) dans un fichier, puis :
    python3 formateur/progression.py chat.txt
    python3 formateur/progression.py chat.txt --anonyme    # pour la projection en fin de J3

Lignes reconnues, n'importe où dans une ligne du chat :
    LAB 07 · 9/9 · poste-04 · 15:42
    INCIDENT 2 · résolu · 7 min · 1 indice · poste-04 · 09:41
    AUTO · 2 1 1 3 2 · poste-04 · 09:35
Pour un même poste, la dernière ligne d'un lab ou d'un incident l'emporte ;
la première ligne AUTO est le début, la dernière la fin.
"""
import re
import sys
from pathlib import Path
from statistics import median

SEP = r"\s*·\s*"
RE_LAB = re.compile(r"LAB (\d\d)" + SEP + r"(\d+)/(\d+)" + SEP + r"(\S+)" + SEP + r"(\d\d:\d\d)")
RE_INC = re.compile(r"INCIDENT ([123])" + SEP + r"(résolu|non résolu)" + SEP + r"(\d+) min" + SEP
                    + r"(\d) indices?" + SEP + r"(\S+)" + SEP + r"(\d\d:\d\d)")
RE_AUTO = re.compile(r"AUTO" + SEP + r"([1-4]) ([1-4]) ([1-4]) ([1-4]) ([1-4])" + SEP + r"(\S+)" + SEP + r"(\d\d:\d\d)")
OBJECTIFS = ["Installer, utiliser", "Déployer", "Mettre à jour", "Mise à l'échelle", "Haute dispo."]


def lire(texte):
    postes = {}
    for ligne in texte.splitlines():
        if m := RE_LAB.search(ligne):
            lab, ok, n, p, _ = m.groups()
            postes.setdefault(p, {"labs": {}, "inc": {}, "auto": []})["labs"][lab] = (int(ok), int(n))
        if m := RE_INC.search(ligne):
            i, etat, mn, ind, p, _ = m.groups()
            postes.setdefault(p, {"labs": {}, "inc": {}, "auto": []})["inc"][i] = (etat == "résolu", int(mn), int(ind))
        if m := RE_AUTO.search(ligne):
            *notes, p, _ = m.groups()
            postes.setdefault(p, {"labs": {}, "inc": {}, "auto": []})["auto"].append([int(x) for x in notes])
    return postes


DUREE_MAX = 120   # au-delà : incident commencé lors d'une séance précédente, durée non significative


def cellule_inc(r):
    if r is None:
        return "—"
    ok, mn, ind = r
    duree = f"{mn:>2}'" if mn <= DUREE_MAX else ">2h?"
    return f"{'ok' if ok else 'KO'} {duree} {ind}i"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    anonyme = "--anonyme" in sys.argv
    texte = Path(args[0]).read_text(encoding="utf-8") if args else sys.stdin.read()
    postes = lire(texte)
    if not postes:
        sys.exit("Aucune ligne LAB, INCIDENT ou AUTO trouvée.")
    noms = sorted(postes)
    etiquette = {p: (f"poste {k + 1:02d}" if anonyme else p) for k, p in enumerate(noms)}
    larg = max(len(e) for e in etiquette.values()) + 2

    print("\nPAR POSTE   (incident : ok/KO, minutes, indices ; labs : terminés à 100 %)")
    print("            (>2h? : incident commencé lors d'une séance précédente, hors temps médian)\n")
    print(f"{'':{larg}}{'incident 1':<14}{'incident 2':<14}{'incident 3':<14}{'labs':<8}auto début → fin")
    for p in noms:
        d = postes[p]
        labs = sum(1 for ok, n in d["labs"].values() if ok == n)
        a = d["auto"]
        auto = (" ".join(map(str, a[0])) + "  →  " + " ".join(map(str, a[-1]))) if len(a) >= 2 else \
               (" ".join(map(str, a[0])) + "  →  ?" if a else "—")
        print(f"{etiquette[p]:<{larg}}" + "".join(f"{cellule_inc(d['inc'].get(i)):<14}" for i in "123")
              + f"{labs:>2}/14   {auto}")

    print("\nGROUPE\n")
    print(f"{'':12}{'résolus':>9}{'sans indice':>13}{'temps médian':>14}")
    for i in "123":
        rs = [d["inc"][i] for d in postes.values() if i in d["inc"]]
        if not rs:
            print(f"incident {i}{'—':>11}")
            continue
        res = [r for r in rs if r[0]]
        seul = [r for r in res if r[2] == 0]
        durees = [r[1] for r in res if r[1] <= DUREE_MAX]
        med = f"{median(durees):.0f} min" if durees else "—"
        print(f"incident {i}{len(res):>8}/{len(rs):<3}{len(seul):>9}/{len(rs):<3}{med:>14}")

    debuts = [d["auto"][0] for d in postes.values() if len(d["auto"]) >= 2]
    fins = [d["auto"][-1] for d in postes.values() if len(d["auto"]) >= 2]
    if debuts:
        print(f"\nAUTO-ÉVALUATION (moyenne sur {len(debuts)} postes ayant les deux mesures, 1 à 4)\n")
        for k, o in enumerate(OBJECTIFS):
            av = sum(x[k] for x in debuts) / len(debuts)
            ap = sum(x[k] for x in fins) / len(fins)
            print(f"  {k + 1}. {o:<22}{av:.1f}  →  {ap:.1f}")
    print()


if __name__ == "__main__":
    main()
