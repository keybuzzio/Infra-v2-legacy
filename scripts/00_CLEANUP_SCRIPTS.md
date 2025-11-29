# 🧹 Nettoyage des Scripts Temporaires

## 📋 Scripts à Conserver

### Scripts Principaux (à garder)

- `00_master_install.sh` : Script maître d'installation
- `00_install_tools_install01.sh` : Installation des outils sur install-01
- `volumes_tool.sh` : Gestion des volumes Hetzner

### Scripts de Diagnostic (à archiver ou supprimer)

Ces scripts ont été créés pendant le diagnostic du problème 504/503. Ils peuvent être archivés ou supprimés :

#### Scripts de Diagnostic 504
- `00_diagnose_504.sh`
- `00_diagnose_504_complete.sh`
- `00_diagnose_504_from_install01.sh`
- `00_diagnose_504_intermittent.sh`
- `00_diagnose_internal_504.sh`
- `00_diagnose_503.sh`
- `00_final_diagnosis_504.sh`

#### Scripts de Test 504
- `00_test_504_from_master.sh`
- `00_test_after_ufw_fix.sh`
- `00_test_connectivity_workers.sh`
- `00_test_from_workers.sh`
- `00_test_ingress_connectivity.sh`
- `00_test_pod_network.sh`
- `00_test_service_final.sh`
- `00_test_stability.sh`
- `00_test_stability_120s.sh`
- `00_final_test_504.sh`
- `00_final_test_after_flannel_fix.sh`

#### Scripts de Correction 504 (tentatives échouées)
- `00_fix_504_complete.sh`
- `00_fix_504_definitive.sh`
- `00_fix_504_final_summary.sh`
- `00_fix_504_keybuzz_complete.sh` ⚠️ **À GARDER** (solution finale)
- `00_fix_ingress_504.sh`
- `00_fix_network_connectivity.sh`
- `00_fix_dns_resolution.sh`

#### Scripts UFW (tentatives multiples)
- `00_add_ufw_all_workers.sh`
- `00_add_ufw_rules_k3s.sh`
- `00_add_ufw_workers_simple.sh`
- `00_apply_ufw_direct.sh`
- `00_apply_ufw_private_ips.sh`
- `00_apply_ufw_rules_all_nodes.sh`
- `00_apply_ufw_workers.sh`
- `00_fix_ufw_all_k3s_nodes.sh`
- `00_fix_ufw_flannel_interface.sh`
- `00_fix_ufw_k3s_direct.sh`
- `00_fix_ufw_k3s_network.sh`
- `00_fix_ufw_k3s_networks_complete.sh`
- `00_fix_ufw_k3s_simple.sh`
- `00_fix_ufw_nodeports_keybuzz.sh` ⚠️ **À GARDER** (solution finale)

#### Scripts iptables/Flannel
- `00_fix_iptables_forward.sh`
- `00_fix_iptables_kube_forward.sh`
- `00_fix_flannel_routing.sh`
- `00_fix_missing_flannel_route.sh`

#### Scripts K3s Services
- `00_fix_k3s_services_clusterip.sh`

#### Scripts Restauration Services
- `00_restore_services.sh`
- `00_restore_services_simple.sh`

#### Scripts DNS/LB
- `00_check_dns_lb_config.sh`

#### Scripts de Validation
- `00_validate_504_fix.sh` ⚠️ **À GARDER** (utile pour validation)

#### Scripts Temporaires KeyBuzz
- `00_create_keybuzz_daemonsets.sh` ⚠️ **À SUPPRIMER** (remplacé par `10_keybuzz_01_deploy_daemonsets.sh`)

## 📁 Organisation Proposée

### Option 1 : Archive

Créer un dossier `archive/` et y déplacer tous les scripts temporaires :

```bash
mkdir -p Infra/scripts/archive/diagnostic_504
mv 00_diagnose_*.sh archive/diagnostic_504/
mv 00_test_*.sh archive/diagnostic_504/
mv 00_fix_*.sh archive/diagnostic_504/  # Sauf ceux à garder
```

### Option 2 : Suppression

Supprimer directement les scripts qui ne sont plus nécessaires.

## ✅ Scripts à Conserver

1. **`00_fix_504_keybuzz_complete.sh`** : Solution finale (peut être archivé)
2. **`00_fix_ufw_nodeports_keybuzz.sh`** : Ouverture ports NodePort (utile)
3. **`00_validate_504_fix.sh`** : Validation (utile pour tests)
4. **`00_create_keybuzz_daemonsets.sh`** : ⚠️ **À SUPPRIMER** (remplacé)

## 🎯 Recommandation

**Archiver** plutôt que supprimer, au cas où on aurait besoin de référencer certaines tentatives.

---

**Date** : 2025-11-20

