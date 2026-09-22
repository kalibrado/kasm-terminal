# kasm-terminal

Bootstrap d'un environnement terminal DEV / DEVOPS / OPS pour :

- une session Kasm Workspaces ;
- une VM Ubuntu ou Debian ;
- un poste utilisateur Ubuntu ou Debian.

Le script est optimise pour l'image `kasmweb/terminal:1.18.0-rolling-weekly`,
basee sur Ubuntu 22.04 LTS, mais il peut aussi etre execute sur une installation
classique Ubuntu ou Debian disposant de `sudo`.

## Installation depuis GitHub

Ouvrir un terminal sur la machine cible, puis executer les commandes suivantes :

```bash
wget --no-check-certificate --no-cache --no-cookies \
	-O bootstrap-kasm.sh \
	https://raw.githubusercontent.com/kalibrado/kasm-terminal/main/bootstrap-kasm.sh

chmod 0755 bootstrap-kasm.sh
sudo ./bootstrap-kasm.sh
```

La commande `wget` utilise volontairement les options suivantes :

- `--no-check-certificate` : desactive la verification du certificat TLS ;
- `--no-cache` : demande de ne pas utiliser de contenu en cache ;
- `--no-cookies` : n'envoie ni ne conserve de cookies ;
- `-O bootstrap-kasm.sh` : enregistre le fichier sous le nom attendu.

Le script doit etre recupere depuis une source de confiance. Lorsque cela est
possible, il est preferable de supprimer `--no-check-certificate` afin de
conserver la verification TLS.

## Execution

Le script doit etre lance avec `sudo` afin de pouvoir installer les paquets
systeme et les binaires dans `/usr/local/bin`. Il detecte l'utilisateur ayant
lance `sudo` et installe sa configuration utilisateur dans son `HOME`.

Sur un poste ou une VM, ouvrir une nouvelle session de terminal apres
l'installation pour utiliser la nouvelle configuration. Dans Kasm, il est
possible de basculer immediatement vers Zsh avec la commande ci-dessous.

Pour passer a Zsh sans fermer la session Kasm :

```bash
exec zsh
```

Le script peut etre relance. Les installations deja presentes sont detectees
et ne sont pas reinstallees.

## Outils installes

### Terminal et systeme

- Zsh, Bash, tmux, screen, Vim et Nano ;
- Oh My Zsh avec `zsh-autosuggestions`, `zsh-syntax-highlighting` et
	`zsh-completions` ;
- Git et Git LFS ;
- outils de diagnostic : `htop`, `btop`, `iotop`, `iftop`, `ncdu`, `lsof`,
	`strace` et `rsync` ;
- outils reseau : `curl`, `wget`, DNS, `ping`, `nmap`, `netcat`, `socat`,
	`ssh`, `traceroute` et `mtr` ;
- outils d'archives, de compilation et de developpement.

### Developpement et DevOps

- Python 3, `pip`, environnements virtuels et fichiers de developpement ;
- Node.js et npm ;
- Go ;
- Rust via `rustup` ;
- `kubectl` ;
- Helm ;
- Terraform depuis le depot officiel HashiCorp ;
- Ansible ;
- `jq`, `yq`, `ripgrep`, `fd`, `fzf`, `bat`, `eza`, `zoxide` et, si
	disponible dans les depots APT, `git-delta`.

### Configuration Zsh

Le fichier `~/.zshrc` est configure avec :

- les plugins Git, Kubernetes, Helm, Terraform, Ansible et Python ;
- des alias pratiques comme `ll`, `k`, `kgp`, `kgs` et `kgn` ;
- les completions Kubernetes ;
- un historique de 100 000 commandes ;
- la fonction `mkcd` pour creer puis ouvrir un repertoire ;
- la fonction `extract` pour extraire les archives courantes.

Si un fichier `~/.zshrc` existe deja, une copie est creee avant modification
dans `~/.zshrc.bootstrap-backup`.

## Docker

Le Docker CLI n'est pas installe par defaut : la variable
`INSTALL_DOCKER_CLI` vaut `false`. Le conteneur Kasm ne fournit pas de daemon
Docker ni de `systemd`.

Pour activer l'installation du client Docker, modifier le script avant son
execution :

```bash
INSTALL_DOCKER_CLI=true
```

Le client seul devra ensuite utiliser un daemon distant via `DOCKER_HOST` ou
un socket Docker monte dans le conteneur.

## Environnement requis

- Ubuntu ou Debian, en VM, sur un poste utilisateur ou dans Kasm ;
- une architecture `amd64` ou `arm64` pour les binaires concernes ;
- une connexion Internet pendant l'installation ;
- un utilisateur disposant de `sudo` ;
- Bash et les commandes systeme standards (`apt-get`, `dpkg`, `curl` et
	`getent`).

Le script refuse les autres systemes d'exploitation. Il ne depend pas de
`systemd` et peut donc fonctionner dans un conteneur Kasm comme sur une VM ou
un poste classique. Il ne doit pas etre execute avec `sh` :

```bash
# Correct
sudo ./bootstrap-kasm.sh

# Incorrect
sh bootstrap-kasm.sh
```

## Persistance Kasm

Cette section concerne uniquement Kasm. Une session Kasm standard est jetable.
Les paquets systeme et les fichiers utilisateur seront perdus a la prochaine
session, sauf si un profil persistant est active cote Kasm.

Avec un profil persistant, le script reutilise les installations existantes et
les controles d'idempotence evitent de tout telecharger a chaque execution.

Sur une VM ou un poste utilisateur classique, les paquets et fichiers restent
installes normalement sur le disque.

## Validation

La fin du script affiche une validation de :

```text
zsh git curl jq yq rg fzf kubectl helm terraform ansible
```

Les messages d'installation et les erreurs sont affiches directement dans le
terminal. En cas d'echec, relancer le script apres avoir verifie la connexion
Internet, les droits `sudo` et la disponibilite des depots APT.