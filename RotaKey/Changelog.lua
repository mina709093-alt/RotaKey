-- 업데이트 내역 (상수팩 업데이트 안내 창에 표시됨). 새 버전이 위로 오게 적습니다.
if not SangsuPack or not SangsuPack.RegisterChangelog then return end

SangsuPack:RegisterChangelog("RotaKey", {
  { ver = "0.10.0",
    "퀵클릭 탭 추가: 파티창·내 초상화·공격대창을 클릭하면 퀵슬롯에 없어도 바로 주문이 시전됩니다. (Clique 방식)",
    "Shift/Ctrl/Alt 조합과 왼쪽·오른쪽·가운데·4·5번 버튼을 자유롭게 섞어 등록할 수 있습니다.",
    "창 오른쪽 위 [퀵클릭] 탭, 또는 /퀵클릭 으로 엽니다. 등록하지 않은 클릭은 원래대로 동작합니다.",
  },
}, "0.9.1")
