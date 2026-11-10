# Kubernetes Temelleri / Kubernetes Fundamentals Reference Manifests

[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-version)

---

## 🇹🇷 Türkçe Bölüm

Ayti.tech portalı olarak Türk bilişim çalışanlarının dil bariyerine takılmadan kendi dillerinde eğitim alabilmeleri için birçok önemli konuda eğitimler hazırlıyoruz. Bu eğitimlerden üçüncüsü olan "Kubernetes Temelleri” eğitiminde bilişim dünyasının son dönemlerde en önemli teknolojilerinden biri olan Kubernetes konusunu derinlemesine öğrenebilmenizi amaçlıyoruz. Eğitim sonunda katılımcıların "Kubernetes ile ilgili tüm temel bilgilere ve container olarak paketlenmiş uygulamaları Kubernetes platformunda çalıştırabilmek ve yönetmek için gerekli donanıma sahip olmaları” hedeflenmektedir. Bu GitHub dizini eğitimde kullanılan tüm temel Kubernetes obje manifestolarının barındırılması için oluşturulmuştur.

# <img src="./banner.jpg">

“Kubernetes Temelleri” eğitimi toplam 7 kısım altında 80 bölüm olarak tasarlandı. İlk giriş kısmında sizlere eğitim içeriği ve ön gereksinimlerle ilgili bilgiler sunuyor, ardından 2. Kısıma geçip biraz teorik ilerleyerek “Kubernetes nedir?” sorusuna bir cevap aramak başta olmak üzere Kubernetes mimarisi ile ilgili bilmemiz gereken ana başlıkları açıklıyoruz. Hemen ardından 3. kısımda ilk Kubernetes ortamımızı kurduktan sonra çeşitli kurulum yöntemlerini öğreniyoruz. Bunu takip eden 4 ve 5. bölümler ise eğitimin kalbi. Uygulamalarla pekiştirilmiş şekilde Kubernetes yapısını ve objelerini görüyoruz. Öğrenme kısmını tamamladıktan sonra 6. Kısımda tüm bu öğrendiklerimizi bir gerçek hayat senaryosu olarak uygulayacağız.

---

## 🇬🇧 English Version

### Overview
This directory contains foundational **Kubernetes YAML reference manifests** organized by resource kind (`pod`, `deployment`, `replicaset`, `statefulset`, `daemonset`, `job`, `cronjob`, `service`, `ingress`, `configmap`, `secret`, `pv-pvc`, `rbac`, `affinity`, `taint-toleration`, `probes`, `resourcequota`, `limitrange`, and `hpa`) for rapid hands-on experimentation and CKA/CKAD exam practice.