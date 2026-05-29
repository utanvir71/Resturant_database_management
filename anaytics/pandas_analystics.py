from pathlib import Path
import argparse

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_DIR = PROJECT_ROOT / "exports"
OUTPUT_DIR = PROJECT_ROOT / "exports"


def read_csv_if_exists(source_dir, filename):
    path = source_dir / filename
    if not path.exists():
        print(f"Missing {path.name}; skipping related summary.")
        return pd.DataFrame()
    return pd.read_csv(path)


def save_summary(df, filename):
    OUTPUT_DIR.mkdir(exist_ok=True)
    output_path = OUTPUT_DIR / filename
    df.to_csv(output_path, index=False)
    print(f"Created {output_path}")


def build_branch_revenue_summary(payments):
    if payments.empty:
        return

    summary = (
        payments.groupby("branch_name", dropna=False)
        .agg(
            paid_orders=("order_id", "count"),
            total_revenue=("amount_paid", "sum"),
            avg_payment=("amount_paid", "mean"),
        )
        .reset_index()
        .sort_values(["total_revenue", "paid_orders"], ascending=False)
    )

    save_summary(summary, "branch_revenue_summary.csv")


def build_menu_sales_summary(order_items):
    if order_items.empty:
        return

    summary = (
        order_items.groupby(["item_name", "category_name"], dropna=False)
        .agg(
            quantity_sold=("quantity", "sum"),
            gross_sales=("line_total", "sum"),
            avg_unit_price=("agreed_unit_price", "mean"),
        )
        .reset_index()
        .sort_values(["quantity_sold", "gross_sales"], ascending=False)
    )

    save_summary(summary, "menu_sales_summary.csv")


def build_reservation_status_summary(reservations):
    if reservations.empty:
        return

    summary = (
        reservations.groupby(["branch_name", "reservation_status"], dropna=False)
        .size()
        .reset_index(name="reservation_count")
        .sort_values(["branch_name", "reservation_count"], ascending=[True, False])
    )

    save_summary(summary, "reservation_status_summary.csv")


def build_feedback_summary(feedback):
    if feedback.empty:
        return

    summary = (
        feedback.groupby("branch_name", dropna=False)
        .agg(
            feedback_count=("feedback_id", "count"),
            avg_rating=("rating", "mean"),
            lowest_rating=("rating", "min"),
            highest_rating=("rating", "max"),
        )
        .reset_index()
        .sort_values(["avg_rating", "feedback_count"], ascending=False)
    )

    save_summary(summary, "feedback_summary.csv")


def build_payment_method_summary(payments):
    if payments.empty:
        return

    summary = (
        payments.groupby("payment_method", dropna=False)
        .agg(
            payment_count=("payment_id", "count"),
            total_amount=("amount_paid", "sum"),
            avg_amount=("amount_paid", "mean"),
        )
        .reset_index()
        .sort_values("total_amount", ascending=False)
    )

    save_summary(summary, "payment_method_summary.csv")


def main():
    parser = argparse.ArgumentParser(
        description="Create pandas summary CSV files from exported restaurant datasets."
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help="Folder containing CSV exports from the Flask analytics page.",
    )
    args = parser.parse_args()

    source_dir = args.source_dir.expanduser().resolve()

    payments = read_csv_if_exists(source_dir, "payments_export.csv")
    order_items = read_csv_if_exists(source_dir, "order_items_export.csv")
    reservations = read_csv_if_exists(source_dir, "reservations_export.csv")
    feedback = read_csv_if_exists(source_dir, "feedback_export.csv")

    build_branch_revenue_summary(payments)
    build_payment_method_summary(payments)
    build_menu_sales_summary(order_items)
    build_reservation_status_summary(reservations)
    build_feedback_summary(feedback)


if __name__ == "__main__":
    main()
