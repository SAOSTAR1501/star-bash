# Prompt flow after WARP setup
echo -e "\n$SEP"
echo -e "${BOLD}${GREEN}✔ Thiết lập Cloudflare WARP hoàn thành!${NC}"
echo -e "$DASH"
echo -e "${BOLD}${WHITE}💡 GỢI Ý BƯỚC TIẾP THEO (Senior DevOps Flow):${NC}"

if ! getent passwd deployer &>/dev/null; then
    echo -e " [1] ${BOLD}→ Tạo user 'deployer' hạn chế & cấu hình SSH Keys${NC} ${RED}[ĐỀ XUẤT]${NC}"
    echo -e " [2] → Cài đặt GitLab Runner bảo mật"
    echo -e " [0] → Quay lại Dashboard chính"
    echo -e "$DASH"
    read -r -p "👉 Nhập lựa chọn của bạn [0-2]: " nc
    case "$nc" in
        1) NEXT_CHOICE="6" ;;
        2) NEXT_CHOICE="7" ;;
        *) NEXT_CHOICE="" ;;
    esac
else
    if ! command -v gitlab-runner &>/dev/null; then
        echo -e " [1] ${BOLD}→ Cài đặt GitLab Runner bảo mật${NC} ${RED}[ĐỀ XUẤT]${NC}"
        echo -e " [2] → Khởi tạo dự án Frontend mới (FE)"
        echo -e " [3] → Khởi tạo dự án Backend mới (BE)"
        echo -e " [0] → Quay lại Dashboard chính"
        echo -e "$DASH"
        read -r -p "👉 Nhập lựa chọn của bạn [0-3]: " nc
        case "$nc" in
            1) NEXT_CHOICE="7" ;;
            2) NEXT_CHOICE="2" ;;
            3) NEXT_CHOICE="3" ;;
            *) NEXT_CHOICE="" ;;
        esac
    else
        echo -e " [1] ${BOLD}→ Khởi tạo dự án Frontend mới (FE)${NC}"
        echo -e " [2] ${BOLD}→ Khởi tạo dự án Backend mới (BE)${NC}"
        echo -e " [0] → Quay lại Dashboard chính"
        echo -e "$DASH"
        read -r -p "👉 Nhập lựa chọn của bạn [0-2]: " nc
        case "$nc" in
            1) NEXT_CHOICE="2" ;;
            2) NEXT_CHOICE="3" ;;
            *) NEXT_CHOICE="" ;;
        esac
    fi
fi
