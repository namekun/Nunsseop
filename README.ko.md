<p align="center"><img src="docs/images/icon.png" width="120" alt="Nunsseop 아이콘"></p>

<h1 align="center">Nunsseop · 눈썹</h1>

<p align="center">
  <b>MacBook 노치, 이제 쓸모 있게.</b><br>
  음악, 통화, 파일, Spotlight 같은 검색, AI 사용량, 에이전트 알림, 일정, 시스템 HUD가 마우스만 올리면 열립니다.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=c86bfa&label=release" alt="최신 버전"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 이상">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-ff5f8f" alt="MIT 라이선스"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="네이티브 Swift">
</p>

<p align="center">
  <a href="README.md">English</a> · <b>한국어</b> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="https://namekun.github.io/Nunsseop/">홈페이지</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="재생 정보와 캘린더가 보이는 펼친 노치">
</p>

화면 위의 작은 아치, 노치를 눈썹이라고 불러 봤습니다. 무료 오픈소스이고, 계정·구독·추적이 없습니다.

## 30초 만에 설치

```sh
brew install --cask namekun/tap/nunsseop
```

[Homebrew](https://brew.sh)가 필요합니다. Homebrew는 격리 플래그를 지워 주기 때문에 앱이 바로 열립니다. 업데이트는 `brew update && brew upgrade --cask nunsseop`으로 하세요. 새 버전이 나오면 설정 → 일반 → 업데이트에서 이 명령을 클립보드에 복사해 줍니다.

macOS 14 Sonoma 이상이면 됩니다. Apple 실리콘과 Intel 모두, 노치가 없는 화면에서도 동작합니다.

## 처음 1분

1. **노치에 마우스를 올려 보세요.** 열립니다. 마우스를 떼면 다시 접혀요.
2. **음악을 틀어 보세요.** Music, Spotify, YouTube Music, 어떤 브라우저든 노치가 알아챕니다. 접힌 노치에는 작은 앨범아트와 이퀄라이저가 남습니다.
3. **노치를 우클릭 → 설정**에서 탭과 순서, 받을 알림, 크기를 고르세요.

Dock 아이콘은 없습니다. Nunsseop은 노치에 삽니다.

## 둘러보기

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="앱, 명령, 설정이 보이는 검색"><br>**검색.** 앱, 파일, 명령, 클립보드, 이모지, 계산을 한 곳에서. 단축키는 원하는 대로. | <img src="docs/images/tab-ai.png" alt="Claude Code와 Codex 사용량"><br>**AI 사용량.** Claude Code와 Codex 한도. 로그인 필요 없음. |
| <img src="docs/images/shelf.png" alt="AirDrop 칸이 있는 선반"><br>**선반.** 파일을 노치에 놓아 두거나 AirDrop으로 바로 보내기. | <img src="docs/images/tab-timer.png" alt="타이머 탭"><br>**타이머.** 카운트다운, 뽀모도로, 스톱워치. 길이는 원하는 대로. |
| <img src="docs/images/tab-tools.png" alt="도구 탭"><br>**도구.** 오디오 출력, 마이크 음소거, 잠자기 방지, 화면 녹화, 색 찍기, 글자 복사. | <img src="docs/images/tab-system.png" alt="기기 배터리가 보이는 시스템 탭"><br>**시스템.** CPU, 메모리, 디스크, 네트워크, 기기 배터리. |
| <img src="docs/images/tab-emoji.png" alt="이모지 선택기"><br>**이모지.** 모든 이모지를 검색하고 클릭 한 번으로 복사. | <img src="docs/images/hud-headphones.png" alt="헤드폰 배터리 HUD"><br>**HUD.** 볼륨, 밝기, AirPods 배터리 등. |
| <img src="docs/images/collapsed-call.png" alt="Zoom 통화 중인 접힌 노치"><br>**통화.** 통화 중인 앱과 통화 시간. | <img src="docs/images/collapsed-idle.png" alt="Claude Code 남은 양과 날씨가 보이는 접힌 노치"><br>**한눈에.** 닫힌 노치 양쪽에 보일 것을 직접 고르기. |

## 할 수 있는 것

**🎵 음악**
- **어떤 앱이든 지금 재생 중.** Music, Spotify, YouTube Music, 그리고 Safari, Chrome, Arc, Dia, Aside 같은 브라우저까지. 앨범아트, 컨트롤, 끌어서 옮기는 진행바.
- **실시간 가사.** [LRCLIB](https://lrclib.net)에서 가져와 제목 아래에, 원하면 작업 중에도 노치 아래에 띄웁니다.
- **미리보기.** 곡이 바뀌면 제목이 잠깐 나왔다 사라집니다.
- **팟캐스트와 긴 영상**에서는 15초 건너뛰기와 재생 속도 버튼(1×~2×)이 나타납니다. 플레이어가 지원할 때만 보여요.

**🗂️ 일 처리**
- **선반.** 파일을 노치에 끌어다 두고 나중에 꺼내세요. 이미지·PDF·영상은 미리보기로 보입니다. 스크린샷과 다 받은 파일이 알아서 들어오게 할 수도 있고, 파일을 끌면서 마우스를 흔들면 커서 옆에 작은 선반이 바로 뜹니다.
- **캘린더와 미리 알림.** 크게 보이는 오늘 날짜, 일정 있는 날에 점이 찍힌 이번 주, 오늘 일정, 노치에서 바로 완료하는 미리 알림. macOS에 추가한 계정(Google, iCloud, Exchange 등)이 모두 되고, 보일 캘린더를 고를 수 있습니다.
- **다가오는 일정.** 시간이 정해진 일정이 시작하기 5분 전에 노치가 제목과 남은 시간을 알려 줍니다. Zoom, Google Meet, Teams, Webex, FaceTime, Whereby, Chime 링크가 있는 일정에는 홈 탭에 초록색 참가 버튼이 붙고, 알림을 누르면 바로 회의에 들어갑니다.
- **Spotlight·Raycast를 대신하는 검색.** 앱(응용 프로그램 폴더 밖에 있는 앱까지), 파일, 시스템 명령과 설정, 클립보드 기록, 이모지(`:`로 시작), `12*(3+4)` 같은 계산을 자주 연 순서로 보여 줍니다. 머리글자도 됩니다. `vsc`라고 치면 Visual Studio Code가 나와요. 화살표로 고르고 Return으로 엽니다.
- **내 단축키.** 기본은 <kbd>⇧⌘Space</kbd>이고, 설정에서 원하는 키 조합을 직접 눌러 바꿀 수 있습니다. macOS나 다른 앱이 이미 쓰는 조합이면 알려 줍니다.
- **타이머, 클립보드 기록, 메모, 이모지 선택기.** 클립보드 기록은 메모리에만 두고, 암호 관리자가 비밀로 표시한 항목은 건너뜁니다. 복사한 링크에서 `utm_`, `fbclid` 같은 추적 파라미터는 지워 줍니다.

**💻 내 Mac**
- **시스템 HUD.** 볼륨, 밝기(DDC 외부 모니터 포함), 키보드 백라이트, 충전, Caps Lock, AirPods 배터리를 노치에 보여 줍니다. 볼륨·밝기 키를 맡아서 시스템 HUD가 뜨지 않게 할 수도 있어요.
- **시스템 상태와 배터리.** CPU, 메모리, 디스크, 네트워크, 그리고 마우스·키보드·트랙패드 배터리. 부족하면 알려 줍니다.
- **카메라·마이크 표시.** 어떤 앱이든 쓰는 동안 노치에 표시가 뜹니다.
- **도구.** 오디오 출력 전환, 앱별 볼륨(실험 기능, macOS 14.2 이상), 마이크 음소거, 잠자기 방지, 화면 녹화, 드라이브 꺼내기, 화면 어디서든 색 찍기, 화면 일부의 글자 복사.
- **날씨, 다운로드, 미러, Dock 앱**도 마우스만 올리면.

**📞 닫혀 있어도**
- **통화.** Zoom, FaceTime, Teams, Slack, Discord, WhatsApp, Google Meet으로 통화하는 동안 닫힌 노치에 통화 앱과 통화 시간이 보입니다. 어떤 앱이 마이크를 쓰는지로 알아내므로 추가 권한은 필요 없습니다. Zoom, FaceTime, Meet은 통화 앱으로 넘어가지 않고 노치에서 마이크와 카메라를 끌 수 있습니다.
- **양쪽에 원하는 것.** 아무것도 재생하지 않을 때 Claude Code·Codex 남은 사용량, 작업 중인 에이전트, 배터리, 날씨, 날짜를 띄워 두세요.
- **음악과 타이머.** 음악이 나오는 동안 작은 앨범아트와 이퀄라이저, 타이머가 도는 동안 남은 시간.
- **다운로드.** Safari나 Chrome에서 받는 파일이 몇 % 받아졌는지. Finder가 파일 아이콘에 보여 주는 진행률을 그대로 받아 오기 때문에 따로 확인하러 다니지 않습니다.

**🤖 개발자를 위해**
- **AI 사용량.** Claude와 Codex의 한도와 초기화 시각, 최근 5시간·7일 토큰 사용량. Claude Code, Codex, gjc, omo, OpenCode 사용량을 모두 합칩니다. 두 도구가 이 Mac에 이미 남기는 파일을 읽으므로 로그인할 게 없습니다.
- **Claude 실시간 한도 (선택).** AI 탭이 Anthropic에서 Claude의 5시간·주간 한도를 받아올지 한 번 묻습니다. 켜면 Claude Code가 키체인에 둔 로그인 정보로 한 시간에 한 번쯤 받아옵니다. 허락하기 전에는 꺼져 있고, 나중에 설정 → 서비스에서 바꿀 수 있습니다.
- **에이전트와 터미널 알림.** Claude Code, Codex, Gemini CLI, OpenCode 훅, Muxy·cmux·herdr 안의 에이전트, tmux와 WezTerm의 벨이 노치에 뜹니다. 알림을 누르면 그 터미널, 창, 탭이 앞으로 나옵니다([설정 방법](#에이전트와-터미널-알림)).
- **알림 탭.** 에이전트, 터미널, 캘린더에서 온 최근 알림 30개를 모아 두고, 아직 안 본 개수를 배지로 보여 줍니다. 누르면 알림이 온 곳으로 돌아갑니다. 기본으로는 꺼져 있고(설정 → 노치 구성), 메모리에만 둡니다.
- **작업 중인 에이전트.** 닫힌 노치에 나를 기다리는 코딩 에이전트 수(노란 손)를 보여 주고, 기다리는 에이전트가 없으면 일하는 에이전트 수(초록 번개)를 보여 줍니다. 지금은 herdr를 따라갑니다.

**🧩 내게 맞게**
- 탭과 순서, 헤더와 접힌 노치에 보일 것, 받을 알림을 고르세요. **꺼 둔 기능은 아예 동작하지 않습니다.**
- macOS 26에서는 펼친 노치와 카드가 Liquid Glass로 그려져 뒤 화면이 은은하게 비칩니다. 유리의 농도를 조절할 수 있고, 100%로 올리면 완전히 검은 노치가 됩니다. 유리를 아예 끌 수도 있습니다.
- 노치가 없는 화면에서는 닫힌 노치가 메뉴 막대 안에 떠 있는 눈썹 로고의 작은 알약이 됩니다. 원하면 유리로도 그려집니다. 한동안 쓰지 않으면 사라졌다가(3~60초, 또는 끄기) 마우스가 닿으면 다시 나타나고, 0.5초쯤 머무르면 열립니다.
- 표시할 화면, 크기, 열리는 지연 시간, 로그인 시 실행, 덮개를 닫았을 때 숨기기도 고를 수 있습니다.
- 아래로 쓸면 열기, 위로 쓸면 닫기, 홈 탭에서 옆으로 쓸면 다음 곡.
- English, 한국어, 日本語, 简体中文, Español, Deutsch, Français. Mac 언어 설정을 따릅니다.

## 자주 묻는 질문

<details>
<summary><b>"Nunsseop을 열 수 없습니다"라고 나와요.</b></summary>

아직 공증되지 않은 앱이라 그렇습니다. Homebrew(`brew install --cask namekun/tap/nunsseop`)로 설치하세요. Homebrew는 격리 플래그를 지워 주기 때문에 앱이 바로 열립니다.
</details>

<details>
<summary><b>음악을 틀어도 아무것도 안 나와요.</b></summary>

Nunsseop은 macOS가 '지금 재생 중'으로 아는 것을 보여 줍니다. 제어 센터에 재생 정보가 뜨는 앱이어야 하는데, 대부분의 앱과 브라우저가 그렇습니다. 막혔을 때의 대체 경로는 [재생 정보를 읽는 방법](#재생-정보를-읽는-방법)을 보세요.
</details>

<details>
<summary><b>Spotlight 대신 쓸 수 있나요?</b></summary>

네. 설정 → 서비스에서 단축키를 누르고 <kbd>⌘Space</kbd>를 누르세요. Spotlight가 쓰고 있다고 알려 주면서 키보드 단축키를 열어 주는데, 거기서 *Spotlight 검색 보기*를 끄면 됩니다. 검색 탭을 숨겨 둬도 단축키로 열립니다.
</details>

<details>
<summary><b>탭이 너무 많아요.</b></summary>

노치를 우클릭 → 설정 → 노치에서 필요 없는 탭을 끄세요. 꺼 둔 기능은 아예 동작하지 않습니다.
</details>

<details>
<summary><b>노치가 없는 Mac이에요.</b></summary>

덮개를 닫고 쓰는 외장 모니터처럼 노치가 없는 화면에서는, 닫힌 노치가 메뉴 막대 안에 떠 있는 눈썹 로고의 작은 알약으로 나타납니다. 마우스를 올리면 눈썹이 치켜올라가고, 열면 화면 위 가장자리에 평소 크기의 노치로 붙습니다. 쓰지 않으면 사라지는데, 끄거나 시간을 바꾸는 건 설정에서 할 수 있습니다. 어느 화면에 띄울지도 설정에서 고르세요.
</details>

<details>
<summary><b>AI 사용량의 Claude 한도가 오래된 값이에요.</b></summary>

기본으로는 Claude의 5시간·주간 %를 다른 도구가 남기는 캐시에서 읽습니다. 터미널에서 Claude Code를 쓸 때 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) HUD가 저장하는 캐시나 gjc의 캐시입니다. 카드에 마지막 갱신 시각이 함께 나옵니다. 설정 → 서비스에서 연결하면 Claude 한도를 Claude Code의 상태 표시줄에서 바로 가져올 수도 있습니다. 그런 도구 없이도 최신 값을 보려면 AI 탭이나 설정 → 서비스에서 Claude 실시간 한도를 켜세요. 토큰 사용량은 항상 실시간입니다.
</details>

<details>
<summary><b>업데이트 후 볼륨 키를 눌러도 Nunsseop HUD가 안 떠요.</b></summary>

0.8.3 이전 버전은 서명 방식 때문에 업데이트할 때마다 macOS가 손쉬운 사용 권한을 잊었습니다. 0.8.3부터는 유지됩니다. 이전 버전에서 올라왔다면 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 Nunsseop을 한 번 지웠다가 다시 허용하세요. 다시 실행하지 않아도 바로 적용됩니다.
</details>

## 에이전트와 터미널 알림

Nunsseop은 이 Mac 안(`127.0.0.1:47750`)에서만 다른 도구의 알림을 받습니다. 요청에는 `~/Library/Application Support/Nunsseop/notify-token`에 저장된 비밀 토큰이 있어야 합니다.

설정 → 알림에서 Claude Code, Codex, Gemini CLI, OpenCode 옆의 **연결**을 누르세요. 이 Mac에서 써 본 도구만 보입니다. Nunsseop이 그 도구의 설정 파일(`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`)을 바꾸거나 `~/.config/opencode/plugins`에 플러그인을 추가하고, 기존 파일은 `.nunsseop-backup` 확장자로 남겨 둡니다. Codex는 `notify` 명령을 하나만 둘 수 있어서, 이미 있던 명령은 Nunsseop 다음에 그대로 실행됩니다. **연결 해제**를 누르면 원래대로 돌아갑니다. 그 뒤에 시작한 세션의 알림이 노치에 뜹니다.

Claude Code를 직접 설정하려면 **Claude Code 훅 명령 복사**를 누르고 `~/.claude/settings.json`에 넣으세요.

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<복사한 명령을 여기에 붙여 넣기>" }] }
    ]
  }
}
```

터미널과 에이전트 앱은 훅 없이 됩니다.

- **Muxy**, **cmux:** 앱이 가진 알림을 읽어 옵니다. 그 앱이 앞에 있을 때는 띄우지 않습니다.
- **herdr:** 모든 세션에서 작업을 마쳤거나 입력을 기다리는 에이전트를 herdr 소켓에서 읽습니다.
- **tmux:** 어느 창의 벨이든 보여 줍니다. 실행 중인 tmux 서버에만 훅을 추가하고 `tmux.conf`는 바꾸지 않습니다.
- **WezTerm:** 설정 → 알림에서 복사한 줄을 `~/.wezterm.lua`에 붙여 넣으면 벨이 뜹니다.

각각 설정 → 알림에 스위치가 있고(WezTerm은 대신 설정 줄을 복사하는 버튼이 있습니다), 그 도구가 설치돼 있을 때만 보입니다. 자체 훅으로 이미 연결된 도구는 두 번 뜨지 않습니다.

어떤 스크립트든 같은 방식으로 보낼 수 있습니다.

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "빌드", "message": "42초 만에 끝났어요"}'
```

## 권한

권한은 그 기능을 처음 쓸 때만 요청합니다.

| 기능 | 권한 | 요청 시점 |
| --- | --- | --- |
| 캘린더 | 캘린더 | 홈 탭에서 *접근 허용*을 누를 때 |
| 미리 알림 | 미리 알림 | 홈 탭에서 *미리 알림 허용*을 누를 때 |
| 미러 | 카메라 | 미러 탭에서 *카메라 허용*을 누를 때 |
| 화면 녹화, 다른 앱 창의 글자 복사 | 화면 기록 | 처음 녹화하거나 글자를 복사할 때 |
| 소리와 함께 녹화 | 마이크 | 마이크 녹음을 켜고 처음 녹화할 때 |
| 볼륨·밝기·키보드 백라이트 키 대체 | 손쉬운 사용 | 설정에서 그 옵션을 켤 때 |
| Music·Spotify·브라우저 대체 재생 정보 | 자동화 | MediaRemote 헬퍼를 쓸 수 없을 때만 |
| 브라우저의 Google Meet·Zoom·Teams 통화 표시 | 자동화(해당 브라우저) | 브라우저가 처음 마이크를 쓸 때 |
| 로그인 시 실행 | 로그인 항목 | 설정에서 켤 때 |

## 개인정보

Nunsseop은 개인 정보를 수집하거나 보내지 않습니다. 인터넷은 아래 경우에만 씁니다.

- 하루 한 번 `api.github.com`에서 새 버전 확인 (끌 수 있음)
- `lrclib.net`에서 실시간 가사 찾기 (끌 수 있음)
- 입력한 도시의 날씨를 `open-meteo.com`에서 가져오기 (도시를 입력하기 전에는 꺼져 있음). Open-Meteo가 도시를 못 찾으면 Apple 지오코더에 위치를 물어봅니다
- MediaRemote 헬퍼를 쓸 수 없을 때만, 알려진 음악 서비스에서 HTTPS로 앨범아트 받기
- Claude 실시간 한도를 켰을 때만, 키체인에 있는 Claude Code 로그인 정보로 한 시간에 한 번쯤 `api.anthropic.com`에 Claude 한도 묻기

나머지는 모두 이 Mac 안에서만 처리됩니다. 알림 서버는 이 Mac에서 오는 연결만 받고, AI 사용량은 Claude 실시간 한도를 켜지 않는 한 로컬 파일에서 읽고, 알림 탭의 알림은 메모리에만 두고, 녹화 파일은 스크린샷 옆에 저장됩니다. 카메라 미리보기는 미러 탭이 열려 있을 때만 켜지고 녹화되지 않습니다. 클립보드 기록은 Nunsseop을 끄면 지워집니다.

## 재생 정보를 읽는 방법

macOS 15.4부터 비공개 MediaRemote 프레임워크는 Apple이 서명한 프로세스에만 응답합니다. Nunsseop은 작은 헬퍼 라이브러리(`Sources/NowPlayingHelper`)를 시스템의 `/usr/bin/perl` 안에서 실행해 재생 정보를 읽고, 재생·일시정지·건너뛰기·위치 이동 명령을 보내고, 결과를 JSON 줄로 앱에 넘깁니다.

비공개 API에 기대는 방식이라 이후 macOS 업데이트로 막힐 수 있습니다. 그러면 Music과 Spotify는 AppleScript로, 브라우저는 미디어 탭을 읽는 방식으로 바뀝니다. 이 대체 경로는 브라우저마다 *Apple Events의 JavaScript 허용*을 켜야 합니다. Dia에는 그 메뉴가 없어서, Nunsseop이 `--enable-applescript-javascript` 옵션으로 Dia를 다시 열어 줍니다.

## 소스에서 빌드

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<버전>.dmg
```

Swift 5.10 이상이 포함된 Xcode 명령줄 도구가 필요합니다. `scripts/bundle.sh`는 Swift 패키지를 빌드해 임시 서명된 앱 번들로 묶습니다.

## 라이선스

[MIT](LICENSE). 이슈와 풀 리퀘스트를 환영합니다.
